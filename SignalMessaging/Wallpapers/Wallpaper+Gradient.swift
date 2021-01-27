//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension Wallpaper {
    var gradientView: UIView? {
        return Theme.isDarkThemeEnabled ? darkGradientView : lightGradientView
    }

    var lightGradientView: UIView? {
        let gradientLayer = CAGradientLayer()
        let transform: CGAffineTransform

        switch self {
        case .starshipGradient:
            gradientLayer.colors = [

              UIColor(red: 0.954, green: 0.864, blue: 0.277, alpha: 1).cgColor,

              UIColor(red: 0.953, green: 0.856, blue: 0.277, alpha: 1).cgColor,

              UIColor(red: 0.951, green: 0.834, blue: 0.276, alpha: 1).cgColor,

              UIColor(red: 0.948, green: 0.8, blue: 0.275, alpha: 1).cgColor,

              UIColor(red: 0.943, green: 0.757, blue: 0.273, alpha: 1).cgColor,

              UIColor(red: 0.938, green: 0.705, blue: 0.271, alpha: 1).cgColor,

              UIColor(red: 0.933, green: 0.649, blue: 0.269, alpha: 1).cgColor,

              UIColor(red: 0.927, green: 0.589, blue: 0.266, alpha: 1).cgColor,

              UIColor(red: 0.92, green: 0.527, blue: 0.263, alpha: 1).cgColor,

              UIColor(red: 0.915, green: 0.467, blue: 0.261, alpha: 1).cgColor,

              UIColor(red: 0.909, green: 0.411, blue: 0.259, alpha: 1).cgColor,

              UIColor(red: 0.904, green: 0.359, blue: 0.256, alpha: 1).cgColor,

              UIColor(red: 0.899, green: 0.316, blue: 0.255, alpha: 1).cgColor,

              UIColor(red: 0.896, green: 0.282, blue: 0.253, alpha: 1).cgColor,

              UIColor(red: 0.894, green: 0.26, blue: 0.252, alpha: 1).cgColor,

              UIColor(red: 0.893, green: 0.252, blue: 0.252, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 1, b: 1, c: -1, d: 0.21, tx: 0.5, ty: -0.11)
        case .woodsmokeGradient:
            gradientLayer.colors = [

              UIColor(red: 0.087, green: 0.087, blue: 0.113, alpha: 1).cgColor,

              UIColor(red: 0.091, green: 0.091, blue: 0.118, alpha: 1).cgColor,

              UIColor(red: 0.104, green: 0.104, blue: 0.133, alpha: 1).cgColor,

              UIColor(red: 0.123, green: 0.123, blue: 0.156, alpha: 1).cgColor,

              UIColor(red: 0.148, green: 0.148, blue: 0.186, alpha: 1).cgColor,

              UIColor(red: 0.177, green: 0.177, blue: 0.221, alpha: 1).cgColor,

              UIColor(red: 0.209, green: 0.209, blue: 0.259, alpha: 1).cgColor,

              UIColor(red: 0.242, green: 0.242, blue: 0.3, alpha: 1).cgColor,

              UIColor(red: 0.277, green: 0.277, blue: 0.341, alpha: 1).cgColor,

              UIColor(red: 0.311, green: 0.311, blue: 0.382, alpha: 1).cgColor,

              UIColor(red: 0.343, green: 0.343, blue: 0.421, alpha: 1).cgColor,

              UIColor(red: 0.372, green: 0.372, blue: 0.456, alpha: 1).cgColor,

              UIColor(red: 0.396, green: 0.396, blue: 0.485, alpha: 1).cgColor,

              UIColor(red: 0.416, green: 0.416, blue: 0.508, alpha: 1).cgColor,

              UIColor(red: 0.428, green: 0.428, blue: 0.523, alpha: 1).cgColor,

              UIColor(red: 0.432, green: 0.432, blue: 0.528, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .coralGradient:
            gradientLayer.colors = [

              UIColor(red: 0.961, green: 0.22, blue: 0.267, alpha: 1).cgColor,

              UIColor(red: 0.952, green: 0.22, blue: 0.27, alpha: 1).cgColor,

              UIColor(red: 0.927, green: 0.219, blue: 0.281, alpha: 1).cgColor,

              UIColor(red: 0.888, green: 0.219, blue: 0.297, alpha: 1).cgColor,

              UIColor(red: 0.838, green: 0.219, blue: 0.318, alpha: 1).cgColor,

              UIColor(red: 0.779, green: 0.219, blue: 0.343, alpha: 1).cgColor,

              UIColor(red: 0.714, green: 0.218, blue: 0.37, alpha: 1).cgColor,

              UIColor(red: 0.645, green: 0.218, blue: 0.399, alpha: 1).cgColor,

              UIColor(red: 0.575, green: 0.217, blue: 0.428, alpha: 1).cgColor,

              UIColor(red: 0.506, green: 0.217, blue: 0.457, alpha: 1).cgColor,

              UIColor(red: 0.441, green: 0.217, blue: 0.485, alpha: 1).cgColor,

              UIColor(red: 0.382, green: 0.216, blue: 0.509, alpha: 1).cgColor,

              UIColor(red: 0.332, green: 0.216, blue: 0.53, alpha: 1).cgColor,

              UIColor(red: 0.293, green: 0.216, blue: 0.546, alpha: 1).cgColor,

              UIColor(red: 0.268, green: 0.216, blue: 0.557, alpha: 1).cgColor,

              UIColor(red: 0.259, green: 0.216, blue: 0.561, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.01, 0.03, 0.06, 0.11, 0.17, 0.23, 0.3, 0.38, 0.47, 0.55, 0.64, 0.73, 0.83, 0.91, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: -1, b: 1, c: -1, d: -0.21, tx: 1.5, ty: 0.11)
        case .ceruleanGradient:
            gradientLayer.colors = [

              UIColor(red: 0, green: 0.576, blue: 0.914, alpha: 1).cgColor,

              UIColor(red: 0.006, green: 0.58, blue: 0.912, alpha: 1).cgColor,

              UIColor(red: 0.024, green: 0.588, blue: 0.907, alpha: 1).cgColor,

              UIColor(red: 0.052, green: 0.601, blue: 0.9, alpha: 1).cgColor,

              UIColor(red: 0.088, green: 0.618, blue: 0.89, alpha: 1).cgColor,

              UIColor(red: 0.13, green: 0.638, blue: 0.879, alpha: 1).cgColor,

              UIColor(red: 0.177, green: 0.661, blue: 0.867, alpha: 1).cgColor,

              UIColor(red: 0.226, green: 0.684, blue: 0.854, alpha: 1).cgColor,

              UIColor(red: 0.276, green: 0.708, blue: 0.84, alpha: 1).cgColor,

              UIColor(red: 0.325, green: 0.731, blue: 0.827, alpha: 1).cgColor,

              UIColor(red: 0.372, green: 0.754, blue: 0.815, alpha: 1).cgColor,

              UIColor(red: 0.414, green: 0.774, blue: 0.804, alpha: 1).cgColor,

              UIColor(red: 0.45, green: 0.791, blue: 0.794, alpha: 1).cgColor,

              UIColor(red: 0.478, green: 0.804, blue: 0.787, alpha: 1).cgColor,

              UIColor(red: 0.496, green: 0.813, blue: 0.782, alpha: 1).cgColor,

              UIColor(red: 0.502, green: 0.816, blue: 0.78, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .roseGradient:
            gradientLayer.colors = [

              UIColor(red: 0.943, green: 0.296, blue: 0.901, alpha: 1).cgColor,

              UIColor(red: 0.932, green: 0.295, blue: 0.901, alpha: 1).cgColor,

              UIColor(red: 0.9, green: 0.291, blue: 0.9, alpha: 1).cgColor,

              UIColor(red: 0.851, green: 0.285, blue: 0.898, alpha: 1).cgColor,

              UIColor(red: 0.787, green: 0.276, blue: 0.895, alpha: 1).cgColor,

              UIColor(red: 0.713, green: 0.267, blue: 0.892, alpha: 1).cgColor,

              UIColor(red: 0.63, green: 0.257, blue: 0.888, alpha: 1).cgColor,

              UIColor(red: 0.543, green: 0.245, blue: 0.885, alpha: 1).cgColor,

              UIColor(red: 0.455, green: 0.234, blue: 0.881, alpha: 1).cgColor,

              UIColor(red: 0.368, green: 0.223, blue: 0.878, alpha: 1).cgColor,

              UIColor(red: 0.285, green: 0.213, blue: 0.874, alpha: 1).cgColor,

              UIColor(red: 0.211, green: 0.203, blue: 0.871, alpha: 1).cgColor,

              UIColor(red: 0.148, green: 0.195, blue: 0.869, alpha: 1).cgColor,

              UIColor(red: 0.098, green: 0.189, blue: 0.867, alpha: 1).cgColor,

              UIColor(red: 0.067, green: 0.185, blue: 0.865, alpha: 1).cgColor,

              UIColor(red: 0.055, green: 0.183, blue: 0.865, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: -1, b: 1, c: -2, d: -0.43, tx: 2, ty: 0.21)
        case .aquamarineGradient:
            gradientLayer.colors = [

              UIColor(red: 0.395, green: 0.805, blue: 0.673, alpha: 1).cgColor,

              UIColor(red: 0.391, green: 0.802, blue: 0.669, alpha: 1).cgColor,

              UIColor(red: 0.378, green: 0.795, blue: 0.657, alpha: 1).cgColor,

              UIColor(red: 0.358, green: 0.784, blue: 0.639, alpha: 1).cgColor,

              UIColor(red: 0.333, green: 0.769, blue: 0.616, alpha: 1).cgColor,

              UIColor(red: 0.303, green: 0.752, blue: 0.589, alpha: 1).cgColor,

              UIColor(red: 0.27, green: 0.733, blue: 0.56, alpha: 1).cgColor,

              UIColor(red: 0.235, green: 0.713, blue: 0.528, alpha: 1).cgColor,

              UIColor(red: 0.199, green: 0.693, blue: 0.496, alpha: 1).cgColor,

              UIColor(red: 0.164, green: 0.673, blue: 0.465, alpha: 1).cgColor,

              UIColor(red: 0.131, green: 0.654, blue: 0.435, alpha: 1).cgColor,

              UIColor(red: 0.101, green: 0.637, blue: 0.408, alpha: 1).cgColor,

              UIColor(red: 0.076, green: 0.622, blue: 0.385, alpha: 1).cgColor,

              UIColor(red: 0.056, green: 0.611, blue: 0.367, alpha: 1).cgColor,

              UIColor(red: 0.043, green: 0.604, blue: 0.356, alpha: 1).cgColor,

              UIColor(red: 0.039, green: 0.601, blue: 0.352, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .tropicalGradient:
            gradientLayer.colors = [

              UIColor(red: 0.846, green: 0.882, blue: 0.981, alpha: 1).cgColor,

              UIColor(red: 0.846, green: 0.879, blue: 0.978, alpha: 1).cgColor,

              UIColor(red: 0.846, green: 0.871, blue: 0.968, alpha: 1).cgColor,

              UIColor(red: 0.846, green: 0.857, blue: 0.953, alpha: 1).cgColor,

              UIColor(red: 0.845, green: 0.84, blue: 0.933, alpha: 1).cgColor,

              UIColor(red: 0.845, green: 0.82, blue: 0.91, alpha: 1).cgColor,

              UIColor(red: 0.844, green: 0.798, blue: 0.885, alpha: 1).cgColor,

              UIColor(red: 0.843, green: 0.775, blue: 0.858, alpha: 1).cgColor,

              UIColor(red: 0.842, green: 0.751, blue: 0.831, alpha: 1).cgColor,

              UIColor(red: 0.842, green: 0.727, blue: 0.804, alpha: 1).cgColor,

              UIColor(red: 0.841, green: 0.705, blue: 0.779, alpha: 1).cgColor,

              UIColor(red: 0.84, green: 0.685, blue: 0.756, alpha: 1).cgColor,

              UIColor(red: 0.84, green: 0.668, blue: 0.737, alpha: 1).cgColor,

              UIColor(red: 0.84, green: 0.655, blue: 0.722, alpha: 1).cgColor,

              UIColor(red: 0.839, green: 0.646, blue: 0.712, alpha: 1).cgColor,

              UIColor(red: 0.839, green: 0.643, blue: 0.708, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1.69, d: 0, tx: 1.34, ty: 0)
        case .blueGradient:
            gradientLayer.colors = [

              UIColor(red: 0.846, green: 0.92, blue: 0.994, alpha: 1).cgColor,

              UIColor(red: 0.843, green: 0.918, blue: 0.994, alpha: 1).cgColor,

              UIColor(red: 0.835, green: 0.914, blue: 0.994, alpha: 1).cgColor,

              UIColor(red: 0.822, green: 0.908, blue: 0.993, alpha: 1).cgColor,

              UIColor(red: 0.806, green: 0.899, blue: 0.992, alpha: 1).cgColor,

              UIColor(red: 0.786, green: 0.889, blue: 0.992, alpha: 1).cgColor,

              UIColor(red: 0.765, green: 0.878, blue: 0.991, alpha: 1).cgColor,

              UIColor(red: 0.742, green: 0.866, blue: 0.99, alpha: 1).cgColor,

              UIColor(red: 0.719, green: 0.854, blue: 0.989, alpha: 1).cgColor,

              UIColor(red: 0.696, green: 0.842, blue: 0.988, alpha: 1).cgColor,

              UIColor(red: 0.675, green: 0.831, blue: 0.987, alpha: 1).cgColor,

              UIColor(red: 0.656, green: 0.821, blue: 0.986, alpha: 1).cgColor,

              UIColor(red: 0.639, green: 0.812, blue: 0.986, alpha: 1).cgColor,

              UIColor(red: 0.626, green: 0.806, blue: 0.985, alpha: 1).cgColor,

              UIColor(red: 0.618, green: 0.802, blue: 0.985, alpha: 1).cgColor,

              UIColor(red: 0.615, green: 0.8, blue: 0.985, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .bisqueGradient:
            gradientLayer.colors = [

              UIColor(red: 1, green: 0.899, blue: 0.76, alpha: 1).cgColor,

              UIColor(red: 1, green: 0.896, blue: 0.758, alpha: 1).cgColor,

              UIColor(red: 0.999, green: 0.888, blue: 0.751, alpha: 1).cgColor,

              UIColor(red: 0.999, green: 0.875, blue: 0.741, alpha: 1).cgColor,

              UIColor(red: 0.998, green: 0.86, blue: 0.727, alpha: 1).cgColor,

              UIColor(red: 0.997, green: 0.841, blue: 0.712, alpha: 1).cgColor,

              UIColor(red: 0.995, green: 0.82, blue: 0.694, alpha: 1).cgColor,

              UIColor(red: 0.994, green: 0.798, blue: 0.676, alpha: 1).cgColor,

              UIColor(red: 0.993, green: 0.776, blue: 0.657, alpha: 1).cgColor,

              UIColor(red: 0.991, green: 0.754, blue: 0.639, alpha: 1).cgColor,

              UIColor(red: 0.99, green: 0.733, blue: 0.622, alpha: 1).cgColor,

              UIColor(red: 0.989, green: 0.715, blue: 0.606, alpha: 1).cgColor,

              UIColor(red: 0.988, green: 0.699, blue: 0.593, alpha: 1).cgColor,

              UIColor(red: 0.987, green: 0.686, blue: 0.582, alpha: 1).cgColor,

              UIColor(red: 0.987, green: 0.678, blue: 0.576, alpha: 1).cgColor,

              UIColor(red: 0.987, green: 0.676, blue: 0.573, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: -1, b: 1, c: -1, d: -0.21, tx: 1.5, ty: 0.11)
        default:
            return nil
        }

        let layerView = OWSLayerView(frame: .zero) { view in
            gradientLayer.aspectFillInBounds(view.bounds, with: transform)
        }
        layerView.layer.addSublayer(gradientLayer)
        layerView.clipsToBounds = true

        return layerView
    }

    var darkGradientView: UIView? {
        let gradientLayer = CAGradientLayer()
        let transform: CGAffineTransform

        switch self {
        case .starshipGradient:
            gradientLayer.colors = [

              UIColor(red: 0.756, green: 0.667, blue: 0.084, alpha: 1).cgColor,

              UIColor(red: 0.754, green: 0.659, blue: 0.084, alpha: 1).cgColor,

              UIColor(red: 0.748, green: 0.638, blue: 0.083, alpha: 1).cgColor,

              UIColor(red: 0.739, green: 0.604, blue: 0.082, alpha: 1).cgColor,

              UIColor(red: 0.728, green: 0.561, blue: 0.081, alpha: 1).cgColor,

              UIColor(red: 0.714, green: 0.511, blue: 0.079, alpha: 1).cgColor,

              UIColor(red: 0.699, green: 0.455, blue: 0.078, alpha: 1).cgColor,

              UIColor(red: 0.683, green: 0.396, blue: 0.076, alpha: 1).cgColor,

              UIColor(red: 0.667, green: 0.336, blue: 0.074, alpha: 1).cgColor,

              UIColor(red: 0.651, green: 0.278, blue: 0.072, alpha: 1).cgColor,

              UIColor(red: 0.636, green: 0.222, blue: 0.071, alpha: 1).cgColor,

              UIColor(red: 0.622, green: 0.171, blue: 0.069, alpha: 1).cgColor,

              UIColor(red: 0.611, green: 0.128, blue: 0.068, alpha: 1).cgColor,

              UIColor(red: 0.602, green: 0.095, blue: 0.067, alpha: 1).cgColor,

              UIColor(red: 0.596, green: 0.074, blue: 0.066, alpha: 1).cgColor,

              UIColor(red: 0.594, green: 0.066, blue: 0.066, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 1, b: 1, c: -1, d: 0.21, tx: 0.5, ty: -0.11)
        case .woodsmokeGradient:
            gradientLayer.colors = [

              UIColor(red: 0.044, green: 0.044, blue: 0.056, alpha: 1).cgColor,

              UIColor(red: 0.047, green: 0.047, blue: 0.061, alpha: 1).cgColor,

              UIColor(red: 0.057, green: 0.057, blue: 0.073, alpha: 1).cgColor,

              UIColor(red: 0.073, green: 0.073, blue: 0.092, alpha: 1).cgColor,

              UIColor(red: 0.093, green: 0.093, blue: 0.116, alpha: 1).cgColor,

              UIColor(red: 0.116, green: 0.116, blue: 0.145, alpha: 1).cgColor,

              UIColor(red: 0.142, green: 0.142, blue: 0.176, alpha: 1).cgColor,

              UIColor(red: 0.17, green: 0.17, blue: 0.209, alpha: 1).cgColor,

              UIColor(red: 0.198, green: 0.198, blue: 0.243, alpha: 1).cgColor,

              UIColor(red: 0.225, green: 0.225, blue: 0.276, alpha: 1).cgColor,

              UIColor(red: 0.251, green: 0.251, blue: 0.308, alpha: 1).cgColor,

              UIColor(red: 0.275, green: 0.275, blue: 0.336, alpha: 1).cgColor,

              UIColor(red: 0.295, green: 0.295, blue: 0.361, alpha: 1).cgColor,

              UIColor(red: 0.31, green: 0.31, blue: 0.38, alpha: 1).cgColor,

              UIColor(red: 0.32, green: 0.32, blue: 0.392, alpha: 1).cgColor,

              UIColor(red: 0.324, green: 0.324, blue: 0.396, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .coralGradient:
            gradientLayer.colors = [

              UIColor(red: 0.714, green: 0.126, blue: 0.163, alpha: 1).cgColor,

              UIColor(red: 0.708, green: 0.127, blue: 0.167, alpha: 1).cgColor,

              UIColor(red: 0.69, green: 0.129, blue: 0.178, alpha: 1).cgColor,

              UIColor(red: 0.662, green: 0.131, blue: 0.194, alpha: 1).cgColor,

              UIColor(red: 0.626, green: 0.135, blue: 0.216, alpha: 1).cgColor,

              UIColor(red: 0.584, green: 0.139, blue: 0.241, alpha: 1).cgColor,

              UIColor(red: 0.538, green: 0.144, blue: 0.269, alpha: 1).cgColor,

              UIColor(red: 0.489, green: 0.149, blue: 0.298, alpha: 1).cgColor,

              UIColor(red: 0.439, green: 0.154, blue: 0.328, alpha: 1).cgColor,

              UIColor(red: 0.39, green: 0.16, blue: 0.357, alpha: 1).cgColor,

              UIColor(red: 0.343, green: 0.164, blue: 0.385, alpha: 1).cgColor,

              UIColor(red: 0.301, green: 0.169, blue: 0.41, alpha: 1).cgColor,

              UIColor(red: 0.265, green: 0.172, blue: 0.431, alpha: 1).cgColor,

              UIColor(red: 0.238, green: 0.175, blue: 0.448, alpha: 1).cgColor,

              UIColor(red: 0.22, green: 0.177, blue: 0.458, alpha: 1).cgColor,

              UIColor(red: 0.213, green: 0.178, blue: 0.462, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: -1, b: 1, c: -1, d: -0.21, tx: 1.5, ty: 0.11)
        case .ceruleanGradient:
            gradientLayer.colors = [

              UIColor(red: 0, green: 0.328, blue: 0.52, alpha: 1).cgColor,

              UIColor(red: 0.003, green: 0.332, blue: 0.521, alpha: 1).cgColor,

              UIColor(red: 0.012, green: 0.343, blue: 0.524, alpha: 1).cgColor,

              UIColor(red: 0.025, green: 0.361, blue: 0.528, alpha: 1).cgColor,

              UIColor(red: 0.042, green: 0.383, blue: 0.533, alpha: 1).cgColor,

              UIColor(red: 0.062, green: 0.41, blue: 0.54, alpha: 1).cgColor,

              UIColor(red: 0.084, green: 0.439, blue: 0.547, alpha: 1).cgColor,

              UIColor(red: 0.107, green: 0.469, blue: 0.555, alpha: 1).cgColor,

              UIColor(red: 0.131, green: 0.501, blue: 0.562, alpha: 1).cgColor,

              UIColor(red: 0.154, green: 0.532, blue: 0.57, alpha: 1).cgColor,

              UIColor(red: 0.176, green: 0.561, blue: 0.577, alpha: 1).cgColor,

              UIColor(red: 0.196, green: 0.587, blue: 0.583, alpha: 1).cgColor,

              UIColor(red: 0.213, green: 0.61, blue: 0.589, alpha: 1).cgColor,

              UIColor(red: 0.226, green: 0.627, blue: 0.593, alpha: 1).cgColor,

              UIColor(red: 0.235, green: 0.638, blue: 0.596, alpha: 1).cgColor,

              UIColor(red: 0.238, green: 0.642, blue: 0.597, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .roseGradient:
            gradientLayer.colors = [

              UIColor(red: 0.684, green: 0.056, blue: 0.644, alpha: 1).cgColor,

              UIColor(red: 0.677, green: 0.057, blue: 0.645, alpha: 1).cgColor,

              UIColor(red: 0.656, green: 0.062, blue: 0.648, alpha: 1).cgColor,

              UIColor(red: 0.624, green: 0.07, blue: 0.652, alpha: 1).cgColor,

              UIColor(red: 0.582, green: 0.08, blue: 0.658, alpha: 1).cgColor,

              UIColor(red: 0.533, green: 0.092, blue: 0.664, alpha: 1).cgColor,

              UIColor(red: 0.478, green: 0.105, blue: 0.671, alpha: 1).cgColor,

              UIColor(red: 0.421, green: 0.119, blue: 0.679, alpha: 1).cgColor,

              UIColor(red: 0.362, green: 0.133, blue: 0.687, alpha: 1).cgColor,

              UIColor(red: 0.305, green: 0.147, blue: 0.694, alpha: 1).cgColor,

              UIColor(red: 0.25, green: 0.16, blue: 0.701, alpha: 1).cgColor,

              UIColor(red: 0.201, green: 0.172, blue: 0.708, alpha: 1).cgColor,

              UIColor(red: 0.159, green: 0.182, blue: 0.714, alpha: 1).cgColor,

              UIColor(red: 0.127, green: 0.19, blue: 0.718, alpha: 1).cgColor,

              UIColor(red: 0.106, green: 0.195, blue: 0.721, alpha: 1).cgColor,

              UIColor(red: 0.098, green: 0.197, blue: 0.722, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: -1, b: 1, c: -2, d: -0.43, tx: 2, ty: 0.21)
        case .aquamarineGradient:
            gradientLayer.colors = [

              UIColor(red: 0.137, green: 0.423, blue: 0.331, alpha: 1).cgColor,

              UIColor(red: 0.135, green: 0.422, blue: 0.329, alpha: 1).cgColor,

              UIColor(red: 0.131, green: 0.419, blue: 0.324, alpha: 1).cgColor,

              UIColor(red: 0.125, green: 0.415, blue: 0.317, alpha: 1).cgColor,

              UIColor(red: 0.116, green: 0.409, blue: 0.308, alpha: 1).cgColor,

              UIColor(red: 0.107, green: 0.401, blue: 0.296, alpha: 1).cgColor,

              UIColor(red: 0.096, green: 0.393, blue: 0.284, alpha: 1).cgColor,

              UIColor(red: 0.085, green: 0.385, blue: 0.271, alpha: 1).cgColor,

              UIColor(red: 0.073, green: 0.377, blue: 0.258, alpha: 1).cgColor,

              UIColor(red: 0.062, green: 0.368, blue: 0.245, alpha: 1).cgColor,

              UIColor(red: 0.052, green: 0.36, blue: 0.232, alpha: 1).cgColor,

              UIColor(red: 0.042, green: 0.353, blue: 0.221, alpha: 1).cgColor,

              UIColor(red: 0.034, green: 0.347, blue: 0.212, alpha: 1).cgColor,

              UIColor(red: 0.027, green: 0.342, blue: 0.204, alpha: 1).cgColor,

              UIColor(red: 0.023, green: 0.339, blue: 0.199, alpha: 1).cgColor,

              UIColor(red: 0.022, green: 0.338, blue: 0.198, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .tropicalGradient:
            gradientLayer.colors = [

              UIColor(red: 0.542, green: 0.632, blue: 0.878, alpha: 1).cgColor,

              UIColor(red: 0.544, green: 0.628, blue: 0.873, alpha: 1).cgColor,

              UIColor(red: 0.55, green: 0.619, blue: 0.859, alpha: 1).cgColor,

              UIColor(red: 0.56, green: 0.604, blue: 0.837, alpha: 1).cgColor,

              UIColor(red: 0.572, green: 0.585, blue: 0.809, alpha: 1).cgColor,

              UIColor(red: 0.587, green: 0.563, blue: 0.775, alpha: 1).cgColor,

              UIColor(red: 0.602, green: 0.538, blue: 0.739, alpha: 1).cgColor,

              UIColor(red: 0.619, green: 0.512, blue: 0.7, alpha: 1).cgColor,

              UIColor(red: 0.637, green: 0.485, blue: 0.66, alpha: 1).cgColor,

              UIColor(red: 0.654, green: 0.459, blue: 0.621, alpha: 1).cgColor,

              UIColor(red: 0.67, green: 0.435, blue: 0.585, alpha: 1).cgColor,

              UIColor(red: 0.684, green: 0.412, blue: 0.551, alpha: 1).cgColor,

              UIColor(red: 0.696, green: 0.393, blue: 0.523, alpha: 1).cgColor,

              UIColor(red: 0.706, green: 0.379, blue: 0.501, alpha: 1).cgColor,

              UIColor(red: 0.712, green: 0.369, blue: 0.487, alpha: 1).cgColor,

              UIColor(red: 0.714, green: 0.366, blue: 0.482, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1.69, d: 0, tx: 1.34, ty: 0)
        case .blueGradient:
            gradientLayer.colors = [

              UIColor(red: 0.627, green: 0.77, blue: 0.913, alpha: 1).cgColor,

              UIColor(red: 0.623, green: 0.767, blue: 0.911, alpha: 1).cgColor,

              UIColor(red: 0.61, green: 0.759, blue: 0.907, alpha: 1).cgColor,

              UIColor(red: 0.591, green: 0.746, blue: 0.901, alpha: 1).cgColor,

              UIColor(red: 0.566, green: 0.73, blue: 0.893, alpha: 1).cgColor,

              UIColor(red: 0.537, green: 0.71, blue: 0.884, alpha: 1).cgColor,

              UIColor(red: 0.504, green: 0.689, blue: 0.874, alpha: 1).cgColor,

              UIColor(red: 0.47, green: 0.666, blue: 0.863, alpha: 1).cgColor,

              UIColor(red: 0.435, green: 0.644, blue: 0.852, alpha: 1).cgColor,

              UIColor(red: 0.401, green: 0.621, blue: 0.841, alpha: 1).cgColor,

              UIColor(red: 0.368, green: 0.6, blue: 0.831, alpha: 1).cgColor,

              UIColor(red: 0.339, green: 0.58, blue: 0.822, alpha: 1).cgColor,

              UIColor(red: 0.314, green: 0.564, blue: 0.814, alpha: 1).cgColor,

              UIColor(red: 0.295, green: 0.551, blue: 0.808, alpha: 1).cgColor,

              UIColor(red: 0.282, green: 0.543, blue: 0.804, alpha: 1).cgColor,

              UIColor(red: 0.278, green: 0.54, blue: 0.802, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .bisqueGradient:
            gradientLayer.colors = [

              UIColor(red: 0.919, green: 0.759, blue: 0.541, alpha: 1).cgColor,

              UIColor(red: 0.917, green: 0.755, blue: 0.537, alpha: 1).cgColor,

              UIColor(red: 0.91, green: 0.741, blue: 0.528, alpha: 1).cgColor,

              UIColor(red: 0.9, green: 0.72, blue: 0.512, alpha: 1).cgColor,

              UIColor(red: 0.887, green: 0.693, blue: 0.493, alpha: 1).cgColor,

              UIColor(red: 0.871, green: 0.661, blue: 0.469, alpha: 1).cgColor,

              UIColor(red: 0.854, green: 0.626, blue: 0.444, alpha: 1).cgColor,

              UIColor(red: 0.836, green: 0.589, blue: 0.417, alpha: 1).cgColor,

              UIColor(red: 0.818, green: 0.551, blue: 0.389, alpha: 1).cgColor,

              UIColor(red: 0.8, green: 0.514, blue: 0.362, alpha: 1).cgColor,

              UIColor(red: 0.783, green: 0.479, blue: 0.337, alpha: 1).cgColor,

              UIColor(red: 0.767, green: 0.448, blue: 0.313, alpha: 1).cgColor,

              UIColor(red: 0.754, green: 0.421, blue: 0.294, alpha: 1).cgColor,

              UIColor(red: 0.744, green: 0.4, blue: 0.278, alpha: 1).cgColor,

              UIColor(red: 0.737, green: 0.386, blue: 0.269, alpha: 1).cgColor,

              UIColor(red: 0.735, green: 0.381, blue: 0.265, alpha: 1).cgColor

            ]

            gradientLayer.locations = [0, 0.08, 0.16, 0.22, 0.29, 0.35, 0.41, 0.47, 0.53, 0.59, 0.65, 0.71, 0.78, 0.84, 0.92, 1]

            gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.5)

            gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.5)

            transform = CGAffineTransform(a: -1, b: 1, c: -1, d: -0.21, tx: 1.5, ty: 0.11)
        default:
            return nil
        }

        let layerView = OWSLayerView(frame: .zero) { view in
            gradientLayer.aspectFillInBounds(view.bounds, with: transform)
        }
        layerView.layer.addSublayer(gradientLayer)
        layerView.clipsToBounds = true

        return layerView
    }
}

extension CGAffineTransform {
    var rotation: CGFloat { atan2(b, a) }
}

fileprivate extension CALayer {
    func aspectFillInBounds(_ fillBounds: CGRect, with layerTransform: CGAffineTransform) {
        bounds = fillBounds

        guard !fillBounds.isEmpty else { return }

        transform = CATransform3DIdentity
        let untransformedLayerFrame = frame

        let boundingRectSize: CGSize

        if layerTransform.rotation.truncatingRemainder(dividingBy: .pi) == 0 {
            // If we rotated by some multiple of 180º, the bounding box is
            // just the fill bounds.
            boundingRectSize = fillBounds.size
        } else if layerTransform.rotation.truncatingRemainder(dividingBy: .halfPi) == 0 {
            // If we rotated by some multiple of 90º that's *not* a multiple
            // of 180º, the aspect ratio of the bounding box is the inverse
            // of the aspect ratio of the fill bounds. We just need to determine
            // the longest side of the fill bounds in order to know the shortest
            // side of the bounding rect.

            let aspectRatio = fillBounds.width / fillBounds.height

            if fillBounds.height > fillBounds.width {
                boundingRectSize = CGSize(
                    width: fillBounds.height / aspectRatio,
                    height: fillBounds.height
                )
            } else {
                boundingRectSize = CGSize(
                    width: fillBounds.width,
                    height: fillBounds.width * aspectRatio
                )
            }
        } else {
            // Since we know the angle of rotation, we can determine the
            // size of the bounding rectangle for the rotated layer such
            // that the layer is *exactly* large enough to completly
            // encompass our viewBounds when they share the same center.

            // First, we calculate both sides of the gradient after transform,
            // each side is the hypotenuse of one of the right triangles we will
            // need to solve in order to determine the height and width of the
            // bounding box.

            let transformedOrigin = untransformedLayerFrame.origin.applying(layerTransform)
            let transformedMaxXMinY = CGPoint(
                x: untransformedLayerFrame.maxX,
                y: untransformedLayerFrame.minY
            ).applying(layerTransform)
            let transformedMinXMaxY = CGPoint(
                x: untransformedLayerFrame.minX,
                y: untransformedLayerFrame.maxY
            ).applying(layerTransform)

            let transformedWidth = transformedOrigin.distance(transformedMaxXMinY)
            let transformedHeight = transformedOrigin.distance(transformedMinXMaxY)

            // Next we solve for both triangles, wherein either the height or width
            // is the hypotenuse and the angle of rotation lives between leg B and
            // the hypotenuse.

            // We normalize the angle of rotation to be:
            // * not negative
            // * not more than 360º
            //
            // We can do this because the bounding box from rotation 20º and -20º
            // are always equivalent.

            let normalizedRotation = abs(layerTransform.rotation).truncatingRemainder(dividingBy: .pi * 2)

            let firstTriangleLegA = transformedWidth * sin(normalizedRotation)
            let firstTriangleLegB = sqrt(pow(transformedWidth, 2) - pow(firstTriangleLegA, 2))

            let secondTriangleLegA = transformedHeight * sin(normalizedRotation)
            let secondTriangleLegB = sqrt(pow(transformedHeight, 2) - pow(secondTriangleLegA, 2))

            // Using the legs of these two triangles, we now know the bounding
            // rect for our layer!

            boundingRectSize = CGSize(
                width: firstTriangleLegB + secondTriangleLegA,
                height: firstTriangleLegA + secondTriangleLegB
            )
        }

        transform = CATransform3DMakeAffineTransform(layerTransform)
        bounds.size = boundingRectSize
        position = fillBounds.center
    }
}
