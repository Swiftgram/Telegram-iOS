import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SGSimpleSettings


class WallpaperNYNode: ASDisplayNode {
    private var emitterLayer: CAEmitterLayer?
    
    func updateLayout(size: CGSize) {
        if self.emitterLayer == nil {
            let particlesLayer = CAEmitterLayer()
            self.emitterLayer = particlesLayer

            self.layer.addSublayer(particlesLayer)
            self.layer.masksToBounds = true
            
            particlesLayer.backgroundColor = UIColor.clear.cgColor
            particlesLayer.emitterShape = .circle
            particlesLayer.emitterMode = .surface
            particlesLayer.renderMode = .oldestLast

            let cell1 = CAEmitterCell()
            switch SGSimpleSettings.shared.nyStyle {
                case SGSimpleSettings.NYStyle.lightning.rawValue:
                    // cell1.contents = generateTintedImage(image: UIImage(bundleImageName: "SwiftgramContextMenu"), color: .white)
                    if let image = UIImage(bundleImageName: "SwiftgramContextMenu") {
                        cell1.contents = paintImage(image, to: UIColor.white.cgColor).cgImage
                    }
                    cell1.name = "lightning"
                    cell1.scale = 0.15
                    cell1.scaleRange = 0.25
                    cell1.birthRate = 10.0
                default:
                    cell1.contents = UIImage(bundleImageName: "SGSnowflake")?.cgImage
                    cell1.name = "snow"
                    cell1.scale = 0.04
                    cell1.scaleRange = 0.15
                    cell1.birthRate = 10.0
            }
            cell1.lifetime = 55.0
            cell1.velocity = 1.0
            cell1.velocityRange = -1.5
            cell1.xAcceleration = 0.33
            cell1.yAcceleration = 1.0
            cell1.emissionRange = .pi
            cell1.spin = -28.6 * (.pi / 180.0)
            cell1.spinRange = 57.2 * (.pi / 180.0)
            cell1.color = UIColor.white.withAlphaComponent(0.58).cgColor
//            cell1.alphaRange = -0.2
            if ProcessInfo.processInfo.isLowPowerModeEnabled || UIAccessibility.isReduceMotionEnabled {
                cell1.birthRate = cell1.birthRate / 3
            }
            particlesLayer.emitterCells = [cell1]
        }
        
        if let emitterLayer = self.emitterLayer {
            var emitterWidthK: CGFloat = 1.5
            switch SGSimpleSettings.shared.nyStyle {
                case SGSimpleSettings.NYStyle.lightning.rawValue:
                    emitterWidthK = 1.5
                default:
                    break
            }
            emitterLayer.emitterPosition = CGPoint(x: 0.0, y: -size.height / 8.0)
            emitterLayer.emitterSize = CGSize(width: size.width * emitterWidthK, height: size.height)
            emitterLayer.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height)
        }
    }
}


func paintImage(_ image: UIImage, to: CGColor) -> UIImage {
    let rect = CGRect(origin: .zero, size: image.size)

    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
    guard let ctx = UIGraphicsGetCurrentContext() else { return image }

    // Flip context
    ctx.translateBy(x: 0, y: image.size.height)
    ctx.scaleBy(x: 1, y: -1)

    // Draw alpha mask
    ctx.setBlendMode(.normal)
    ctx.clip(to: rect, mask: image.cgImage!)

    // Fill with white
    ctx.setFillColor(to)
    ctx.fill(rect)

    let result = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return result ?? image
}

