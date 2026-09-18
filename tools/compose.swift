//
//  compose.swift
//  App Store用スクリーンショット合成ツール
//
//  スクリーンショットをそのまま貼るのではなく、見せたい部分を切り抜いて
//  拡大配置する。全体像より「何ができるか」が伝わりやすいため。
//
//  使い方:
//    swift compose.swift --in <png> --out <png> \
//      --title "1行目" --sub "2行目" \
//      [--crop x,y,w,h]   # 元画像に対する割合(0-1)。省略時は全体
//      [--scale 0.82]     # 出力幅に対する配置幅の割合
//      [--accent "#FF9D55"]
//      [--in2 <png>]      # 渡すと2枚を横に並べる（配色の比較など）
//      [--labels "左,右"]  # 2枚並べたときに各画像の下へ付ける見出し
//      [--stack]          # 2枚を横ではなく上下に並べる
//

import AppKit
import CoreGraphics

// MARK: - 引数

var opts: [String: String] = [:]
var i = 1
let argv = CommandLine.arguments
while i < argv.count {
    let key = argv[i]
    guard key.hasPrefix("--"), i + 1 < argv.count else { i += 1; continue }
    opts[String(key.dropFirst(2))] = argv[i + 1]
    i += 2
}

/// ストアが要求するサイズ（縦向き）。--width / --height を決めるときの参照用。
/// 横向きで出すときは縦横を入れ替える。
let storeSizes: [(name: String, w: Int, h: Int)] = [
    ("iPhone 6.9インチ  ★これ1セットで足りる", 1320, 2868),
    ("iPhone 6.5インチ  6.9がない場合に必須", 1284, 2778),
    ("iPhone 6.3インチ  任意", 1179, 2556),
    ("iPhone 6.1インチ  任意", 1170, 2532),
    ("iPad 13インチ     ★iPad対応なら必須", 2064, 2752),
    ("iPad 12.9インチ   任意", 2048, 2732),
    ("iPad 11インチ     任意", 1488, 2266),
    ("Google Play       縦9:16の下限", 1080, 1920),
]

func printSizes() {
    print("")
    print("  ストアが要求するサイズ（縦向き / 横向きは縦横を入れ替える）")
    print("  " + String(repeating: "-", count: 46))
    // 数字を先に出す。日本語混じりのラベルを先にすると桁が揃わないため。
    for s in storeSizes {
        print("  " + String(format: "%4d × %4d", s.w, s.h) + "   \(s.name)")
    }
    print("")
    print("  iPhoneは上位サイズを入れれば下位へ自動縮小される。")
    print("  iPadは別枠なので、iPad対応するなら13インチを別に用意する。")
    print("")
}

guard let inPath = opts["in"], let outPath = opts["out"] else {
    print("""
    usage: compose.swift --in <png> --out <png> --title <text> [--sub <text>]
                         [--crop x,y,w,h] [--scale 0.82] [--accent #RRGGBB]
                         [--in2 <png>] [--labels "左,右"] [--stack]
                         [--width 1320] [--height 2868] [--bg "#RRGGBB,#RRGGBB"]
    """)
    printSizes()
    exit(1)
}
let title = opts["title"] ?? ""
let sub = opts["sub"] ?? ""
let scale = CGFloat(Double(opts["scale"] ?? "0.82") ?? 0.82)

func parseHex(_ s: String?) -> CGColor {
    guard var h = s else { return CGColor(red: 1.0, green: 0.62, blue: 0.33, alpha: 1) }
    if h.hasPrefix("#") { h.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: h).scanHexInt64(&v)
    return CGColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let accent = parseHex(opts["accent"])

// MARK: - 出力サイズ

// 既定は App Store の 6.9インチ（1320 × 2868）。
// Google Play は「最大寸法 ≤ 最小寸法 × 2」の制約があり、この比率は使えない。
let W = Int(opts["width"] ?? "") ?? 1320
let H = Int(opts["height"] ?? "") ?? 2868

// 文字の大きさや余白は 1320 幅を基準に決めてある。
// サイズを変えたときは同じ比率で拡縮しないと、字だけ大きいまま残る。
let k = CGFloat(W) / 1320

/// 背景のグラデーション色。--bg "#RRGGBB,#RRGGBB,#RRGGBB" で差し替える。
/// アプリごとに変えないと、並べたときに同じ人が作ったものだと分かってしまう。
let bgColors: [CGColor] = {
    guard let spec = opts["bg"] else {
        return [
            CGColor(red: 0.09, green: 0.08, blue: 0.14, alpha: 1),
            CGColor(red: 0.15, green: 0.12, blue: 0.19, alpha: 1),
            CGColor(red: 0.08, green: 0.12, blue: 0.13, alpha: 1)
        ]
    }
    let colors = spec.split(separator: ",").map { parseHex(String($0)) }
    return colors.count >= 2 ? colors : colors + colors  // 1色だけなら単色塗りになる
}()

// MARK: - 入力画像（必要なら切り抜き）

func loadImage(_ path: String) -> CGImage {
    guard let src = NSImage(contentsOfFile: path),
          let img = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("入力画像を読めません: \(path)"); exit(1)
    }
    return img
}

/// 割合指定で切り抜く。指定がなければそのまま返す
func cropIfNeeded(_ img: CGImage, _ spec: String?) -> CGImage {
    guard let spec else { return img }
    let p = spec.split(separator: ",").compactMap { Double($0) }
    guard p.count == 4 else { return img }
    let iw = CGFloat(img.width), ih = CGFloat(img.height)
    // 指定は左上原点。CGImageのcroppingも左上原点なのでそのまま使える
    let rect = CGRect(x: CGFloat(p[0]) * iw, y: CGFloat(p[1]) * ih,
                      width: CGFloat(p[2]) * iw, height: CGFloat(p[3]) * ih)
    return img.cropping(to: rect) ?? img
}

let cg = cropIfNeeded(loadImage(inPath), opts["crop"])

// --in2 を渡すと2枚を横に並べる。配色の違いのように、
// 並べないと伝わらないものを1枚で見せるため。切り抜きは両方に同じものを適用する。
let cg2 = opts["in2"].map { cropIfNeeded(loadImage($0), opts["crop"]) }

// MARK: - 描画

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("コンテキスト生成失敗"); exit(1)
}

// 背景
let stops = bgColors.count == 1
    ? [0.0, 1.0]
    : (0..<bgColors.count).map { CGFloat($0) / CGFloat(bgColors.count - 1) }
if let g = CGGradient(colorsSpace: cs, colors: bgColors as CFArray, locations: stops) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(H)),
                           end: CGPoint(x: CGFloat(W), y: 0), options: [])
}

/// centerX を省くと出力全体の中央に置く。
/// 2枚並べたときのラベルは、それぞれの画像の中央に寄せたいので指定する。
func drawCentered(_ text: String, size: CGFloat, y: CGFloat, color: CGColor,
                  weight: NSFont.Weight, centerX: CGFloat? = nil) {
    guard !text.isEmpty else { return }
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .paragraphStyle: style
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let b = CTLineGetBoundsWithOptions(line, [])
    ctx.textPosition = CGPoint(x: (centerX ?? CGFloat(W) / 2) - b.width / 2, y: y)
    CTLineDraw(line, ctx)
}

// キャプション
drawCentered(title, size: 112 * k, y: CGFloat(H) - 320 * k, color: CGColor(gray: 1, alpha: 1), weight: .heavy)
drawCentered(sub, size: 62 * k, y: CGFloat(H) - 440 * k, color: CGColor(gray: 1, alpha: 0.62), weight: .medium)

// アクセントの下線
let barW: CGFloat = 132 * k, barH: CGFloat = 10 * k
ctx.setFillColor(accent)
ctx.fill(CGRect(x: (CGFloat(W) - barW) / 2, y: CGFloat(H) - 530 * k, width: barW, height: barH))

// MARK: - 画像本体

/// 角丸・影・縁取りをつけて1枚描く
func drawShot(_ img: CGImage, in rect: CGRect, radius: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20 * k), blur: 56 * k,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.draw(img, in: rect)
    ctx.restoreGState()

    // 縁取り
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.setLineWidth(3 * k)
    ctx.strokePath()
}

// キャプションの直下に置く。
// 領域内で中央寄せにすると、横長の切り抜きのときに
// キャプションとの間が大きく空いてしまうため。
let areaTop = CGFloat(H) - 660 * k
let minBottom: CGFloat = 150 * k

// --labels "SV,旧HOME" で各画像の下に見出しを付ける
let labels = (opts["labels"] ?? "")
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespaces) }
let labelSize: CGFloat = 54 * k
let labelGap: CGFloat = 30 * k

if let cg2 {
    let gap: CGFloat = 36 * k
    let labelSpace = labels.count == 2 ? labelSize + labelGap : 0
    // 2枚のときはキャプション直下に固定せず、使える領域の縦中央に寄せる。
    // 1枚あたりが小さくなるぶん、下に大きな余白が残ってしまうため。
    let available = areaTop - minBottom
    let labelOffset = labelGap + labelSize * 0.78
    let labelColor = CGColor(gray: 1, alpha: 0.88)

    if opts["stack"] != nil {
        // 上下に並べる。横に並べるより1枚を大きく見せられるので、
        // ホイールのように横幅をいっぱいに使う画面はこちらが見やすい。
        let imgW = CGFloat(W) * scale
        let imgH = imgW * CGFloat(cg.height) / CGFloat(cg.width)
        let blockH = (imgH + labelSpace) * 2 + gap
        let bottom = minBottom + max(0, (available - blockH) / 2)
        let x = (CGFloat(W) - imgW) / 2
        let yLower = bottom + labelSpace
        let yUpper = yLower + imgH + gap + labelSpace

        drawShot(cg, in: CGRect(x: x, y: yUpper, width: imgW, height: imgH), radius: 40 * k)
        drawShot(cg2, in: CGRect(x: x, y: yLower, width: imgW, height: imgH), radius: 40 * k)

        if labels.count == 2 {
            drawCentered(labels[0], size: labelSize, y: yUpper - labelOffset,
                         color: labelColor, weight: .semibold)
            drawCentered(labels[1], size: labelSize, y: yLower - labelOffset,
                         color: labelColor, weight: .semibold)
        }
    } else {
        // 横に並べる
        let totalW = CGFloat(W) * scale
        let eachW = (totalW - gap) / 2
        let eachH = eachW * CGFloat(cg.height) / CGFloat(cg.width)
        let y = minBottom + max(0, (available - (eachH + labelSpace)) / 2) + labelSpace
        let leftX = (CGFloat(W) - totalW) / 2
        let rightX = leftX + eachW + gap

        // 幅が半分になるぶん、角丸も小さくしないと丸すぎて見える
        drawShot(cg, in: CGRect(x: leftX, y: y, width: eachW, height: eachH), radius: 30 * k)
        drawShot(cg2, in: CGRect(x: rightX, y: y, width: eachW, height: eachH), radius: 30 * k)

        if labels.count == 2 {
            drawCentered(labels[0], size: labelSize, y: y - labelOffset,
                         color: labelColor, weight: .semibold, centerX: leftX + eachW / 2)
            drawCentered(labels[1], size: labelSize, y: y - labelOffset,
                         color: labelColor, weight: .semibold, centerX: rightX + eachW / 2)
        }
    }
} else {
    let imgW = CGFloat(W) * scale
    let imgH = imgW * CGFloat(cg.height) / CGFloat(cg.width)
    let y = max(minBottom, areaTop - imgH)
    drawShot(cg, in: CGRect(x: (CGFloat(W) - imgW) / 2, y: y, width: imgW, height: imgH), radius: 48 * k)
}

guard let out = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else {
    print("生成失敗"); exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
// どのストア向けのサイズで出したのかを毎回示す。
// この画像を元に別サイズを作るとき、何が必要かすぐ分かるようにするため。
if let match = storeSizes.first(where: { $0.w == W && $0.h == H }) {
    print("生成: \(outPath)  \(W) × \(H)  → \(match.name.trimmingCharacters(in: .whitespaces))")
} else {
    print("生成: \(outPath)  \(W) × \(H)  → 既知のストアサイズと一致しません")
    printSizes()
}
