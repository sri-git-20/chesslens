"""Keras models matching the contract in docs/ARCHITECTURE.md.

* detector: [B,384,384,1] -> [B,96,96,9]   (ch 0 sigmoid heat, ch 1-8 linear offsets / 384)
* corners : [B,256,256,1] -> [B,64,64,4]   (sigmoid heatmaps TL, TR, BR, BL)
* squares : [B,256,256,1] -> [B,8,8,13]    (softmax per square)

Only plain TFLite built-in ops are used (Conv2D, ReLU, nearest upsampling, Add,
Concatenate, Sigmoid, Softmax); batch norm is folded at export.
Input is greyscale in [0, 1]; there is no preprocessing inside the models.
"""
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers


def cbr(x, f, k=3, s=1):
    x = layers.Conv2D(f, k, strides=s, padding="same", use_bias=False)(x)
    x = layers.BatchNormalization(momentum=0.95)(x)
    return layers.ReLU()(x)


def up(x):
    return layers.UpSampling2D(2, interpolation="nearest")(x)


def merge(coarse, skip, ch):
    """FPN-style top-down merge: upsample coarse, 1x1 project both, add, 3x3 conv."""
    a = layers.Conv2D(ch, 1, padding="same")(up(coarse))
    b = layers.Conv2D(ch, 1, padding="same")(skip)
    return cbr(layers.Add()([a, b]), ch)


def build_detector(batch=None):
    inp = keras.Input(batch_shape=(batch, 384, 384, 1), name="image")
    x = cbr(inp, 12, s=2)                    # 192
    f96 = cbr(x, 24, s=2)                    # 96
    x = cbr(f96, 32, s=2); f48 = cbr(x, 32)  # 48
    x = cbr(f48, 64, s=2); x = cbr(x, 64); f24 = cbr(x, 64)      # 24
    x = cbr(f24, 96, s=2); x = cbr(x, 96); f12 = cbr(x, 96)      # 12
    x = cbr(f12, 128, s=2); f6 = cbr(x, 128)                     # 6
    d = merge(f6, f12, 64)       # 12
    d = merge(d, f24, 48)        # 24
    d = merge(d, f48, 32)        # 48
    d = merge(d, f96, 16)        # 96
    heat = layers.Conv2D(1, 1, padding="same", activation="sigmoid",
                         bias_initializer=keras.initializers.Constant(-4.6))(d)
    off = layers.Conv2D(8, 1, padding="same")(d)
    out = layers.Concatenate(name="detector_out")([heat, off])
    return keras.Model(inp, out, name="detector")


def build_corners(batch=None):
    inp = keras.Input(batch_shape=(batch, 256, 256, 1), name="image")
    x = cbr(inp, 16, s=2)                    # 128
    f64 = cbr(x, 24, s=2)                    # 64
    x = cbr(f64, 32, s=2); f32 = cbr(x, 32)  # 32
    x = cbr(f32, 64, s=2); x = cbr(x, 64); f16 = cbr(x, 64)      # 16
    x = cbr(f16, 96, s=2); x = cbr(x, 96); f8 = cbr(x, 96)       # 8
    x = cbr(f8, 128, s=2); f4 = cbr(x, 128)                      # 4
    d = merge(f4, f8, 96)        # 8
    d = merge(d, f16, 64)        # 16
    d = merge(d, f32, 48)        # 32
    d = merge(d, f64, 24)        # 64
    d = cbr(d, 24)
    out = layers.Conv2D(4, 1, padding="same", activation="sigmoid", name="corners_out",
                        bias_initializer=keras.initializers.Constant(-4.6))(d)
    return keras.Model(inp, out, name="corners")


def build_squares(batch=None):
    """v2: more depth at 32x32 / 16x16 / 8x8 where the piece shapes are resolved
    (about 1.0M parameters, ~2 MB as float16)."""
    inp = keras.Input(batch_shape=(batch, 256, 256, 1), name="image")
    x = cbr(inp, 24, s=2)                                   # 128
    x = cbr(x, 40, s=2); x = cbr(x, 40)                     # 64
    x = cbr(x, 64, s=2); x = cbr(x, 64); x = cbr(x, 64)     # 32
    x = cbr(x, 112, s=2); x = cbr(x, 112); x = cbr(x, 112)  # 16
    x = cbr(x, 176, s=2); x = cbr(x, 176); x = cbr(x, 176)  # 8
    out = layers.Conv2D(13, 1, padding="same", activation="softmax", name="squares_out")(x)
    return keras.Model(inp, out, name="squares")


BUILDERS = {"detector": build_detector, "corners": build_corners, "squares": build_squares}
