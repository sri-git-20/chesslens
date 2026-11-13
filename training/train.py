"""Train one model for a fixed wall-clock budget.

    python train.py --model squares --data work/data --minutes 55

The learning-rate schedule is a function of elapsed time (warm-up, cosine to ~0),
so the run ends in a converged state whatever the machine speed. Weights are
stored as a list of arrays (np.savez) and re-loaded into a batch-1 copy of the
architecture at export time.
"""
import argparse
import json
import math
import os
import time

import numpy as np
import tensorflow as tf
from tensorflow import keras

import models
import synth


# ------------------------------------------------------------------ losses
def det_loss(yt, yp):
    """CenterNet focal loss on the centre heat-map + masked L1 on corner offsets.
    yt: [B,96,96,10] = heat, mask, 8 offsets."""
    t, m, ot = yt[..., 0], yt[..., 1], yt[..., 2:]
    p = tf.clip_by_value(yp[..., 0], 1e-4, 1 - 1e-4)
    pos = tf.cast(t >= 0.999, tf.float32)
    pos_l = -tf.math.log(p) * tf.pow(1 - p, 2) * pos
    neg_l = -tf.math.log(1 - p) * tf.pow(p, 2) * tf.pow(1 - t, 4) * (1 - pos)
    npos = tf.maximum(tf.reduce_sum(pos, [1, 2]), 1.0)
    focal = (tf.reduce_sum(pos_l, [1, 2]) + tf.reduce_sum(neg_l, [1, 2])) / npos
    l1 = tf.reduce_sum(tf.abs(yp[..., 1:] - ot) * m[..., None], [1, 2, 3]) * 384.0 / (npos * 9 * 8)
    return focal + 0.1 * l1


def sq_loss(yt, yp):
    """Per-square cross-entropy, occupied squares weighted x2 (empties dominate)."""
    ce = keras.losses.sparse_categorical_crossentropy(yt, yp)
    w = 1.0 + tf.cast(yt > 0, tf.float32)
    return tf.reduce_mean(ce * w, axis=[1, 2])


def cor_loss(yt, yp):
    p = tf.clip_by_value(yp, 1e-5, 1 - 1e-5)
    bce = -(yt * tf.math.log(p) + (1 - yt) * tf.math.log(1 - p))
    return tf.reduce_sum(bce, [1, 2, 3]) / 4.0


# ------------------------------------------------------------------ data
def make_source(name, data, split):
    """Returns (n, fn(idx)->(x uint8 [B,H,W], y float/int array))."""
    d = lambda f: np.load(os.path.join(data, f), mmap_mode="r")
    if name == "detector":
        x, q, n = d("det_x.npy"), d("det_q.npy"), d("det_n.npy")

        def fn(idx):
            ys = np.zeros((len(idx), 96, 96, 10), np.float32)
            for j, i in enumerate(idx):
                h, m, o = synth.det_target(q[i, :n[i]])
                ys[j, ..., 0], ys[j, ..., 1], ys[j, ..., 2:] = h, m, o
            return x[idx], ys
        total = len(x)
    elif name == "corners":
        x, y = d("cor_x.npy"), d("cor_y.npy")

        def fn(idx):
            return x[idx], np.stack([synth.cor_target(y[i]) for i in idx])
        total = len(x)
    else:
        x, y = d("sq_x.npy"), d("sq_y.npy")

        def fn(idx):
            return x[idx], y[idx].astype(np.int32)
        total = len(x)
    nval = max(64, int(0.03 * total))
    # pages/boards are written in generation order, so a tail split is a fair val set
    lo, hi = (0, total - nval) if split == "train" else (total - nval, total)
    return lo, hi, fn


def batches(lo, hi, fn, bs, shuffle, seed=0):
    rng = np.random.default_rng(seed)
    while True:
        idx = np.arange(lo, hi)
        if shuffle:
            rng.shuffle(idx)
        for i in range(0, len(idx) - bs + 1, bs):
            yield fn(np.sort(idx[i:i + bs]))
        if not shuffle:
            return


def make_ds(name, data, split, bs, augment):
    lo, hi, fn = make_source(name, data, split)
    ysig = {"detector": tf.TensorSpec([None, 96, 96, 10], tf.float32),
            "corners": tf.TensorSpec([None, 64, 64, 4], tf.float32),
            "squares": tf.TensorSpec([None, 8, 8], tf.int32)}[name]
    ds = tf.data.Dataset.from_generator(
        lambda: batches(lo, hi, fn, bs, split == "train"),
        output_signature=(tf.TensorSpec([None, None, None], tf.uint8), ysig))

    def prep(x, y):
        x = tf.cast(x, tf.float32)[..., None] / 255.0
        if augment:  # cheap photometric jitter on top of the baked-in degradations
            b = tf.shape(x)[0]
            c = tf.random.uniform([b, 1, 1, 1], 0.75, 1.15)
            br = tf.random.uniform([b, 1, 1, 1], -0.08, 0.08)
            ns = tf.random.uniform([b, 1, 1, 1], 0.0, 0.03)
            x = (x - 0.5) * c + 0.5 + br + tf.random.normal(tf.shape(x)) * ns
            x = tf.clip_by_value(x, 0.0, 1.0)
        return x, y
    ds = ds.map(prep, num_parallel_calls=2).prefetch(4)
    return ds, hi - lo


class TimeBudget(keras.callbacks.Callback):
    def __init__(self, minutes, lr, warm=0.03):
        super().__init__()
        self.budget, self.lr, self.warm = minutes * 60.0, lr, warm
        self.t0 = None

    def on_train_begin(self, logs=None):
        self.t0 = time.time()

    def _frac(self):
        return (time.time() - self.t0) / self.budget

    def on_train_batch_begin(self, batch, logs=None):
        f = min(self._frac(), 1.0)
        lr = self.lr * min(1.0, 0.05 + f / self.warm) * (0.5 * (1 + math.cos(math.pi * f)) * 0.995 + 0.005)
        self.model.optimizer.learning_rate.assign(lr)

    def on_train_batch_end(self, batch, logs=None):
        if self._frac() >= 1.0:
            self.model.stop_training = True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, choices=list(models.BUILDERS))
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", default="work/models")
    ap.add_argument("--minutes", type=float, default=30)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--steps-per-epoch", type=int, default=250)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    keras.utils.set_random_seed(1234)
    model = models.BUILDERS[args.model]()
    print(f"{args.model}: {model.count_params():,} params", flush=True)
    opt = keras.optimizers.Adam(args.lr, clipnorm=5.0)
    if args.model == "detector":
        model.compile(opt, loss=det_loss)
    elif args.model == "corners":
        model.compile(opt, loss=cor_loss)
    else:
        model.compile(opt, loss=sq_loss,
                      metrics=[keras.metrics.SparseCategoricalAccuracy(name="acc")])
    tr, ntr = make_ds(args.model, args.data, "train", args.batch, True)
    va, nva = make_ds(args.model, args.data, "val", args.batch, False)
    print(f"train samples {ntr}, val samples {nva}, budget {args.minutes} min", flush=True)
    t0 = time.time()
    hist = model.fit(tr, validation_data=va, validation_steps=min(20, nva // args.batch),
                     steps_per_epoch=args.steps_per_epoch, epochs=100000, verbose=2,
                     callbacks=[TimeBudget(args.minutes, args.lr)])
    secs = time.time() - t0
    np.savez(os.path.join(args.out, args.model + ".npz"), *model.get_weights())
    steps = len(hist.history["loss"]) * args.steps_per_epoch
    info = dict(model=args.model, params=int(model.count_params()), seconds=secs, steps=steps,
                batch=args.batch, samples_seen=steps * args.batch,
                final={k: float(v[-1]) for k, v in hist.history.items()})
    json.dump(info, open(os.path.join(args.out, args.model + "_train.json"), "w"), indent=1)
    print("done", json.dumps(info), flush=True)


if __name__ == "__main__":
    main()
