# app-support

公開アプリのサポートページとプライバシーポリシー、およびストア提出用の共通ツール置き場。

GitHub Pages で公開している。App Store Connect に登録するURLはここを指す。

## URL

| アプリ | 種別 | URL |
|-------|------|-----|
| ポケタイプ | サポート | https://waltryusan.github.io/app-support/poketype/ |
| ポケタイプ | プライバシーポリシー | https://waltryusan.github.io/app-support/poketype/privacy.html |

## 構成

```
app-support/
├── index.html          # アプリ一覧
├── poketype/
│   ├── index.html      # サポート（使い方・FAQ・問い合わせ）
│   └── privacy.html    # プライバシーポリシー
└── tools/
    └── compose.swift   # スクリーンショット合成ツール
```

アプリを追加するときは、そのアプリ名のディレクトリを作って
`index.html` と `privacy.html` を置き、ルートの `index.html` にリンクを足す。

## サポートURLについて

**Googleフォームを直接サポートURLに指定しない。**
Apple はサポートURLに「サポート情報が掲載されたページ」を求めており（Guideline 1.5）、
フォーム単体だと情報が無いと判断され得る。

使い方とFAQを載せたページを置き、フォームはその中からリンクする。

## tools/compose.swift

App Store / Google Play 向けのスクリーンショットを合成する。
スクリーンショットをそのまま貼るのではなく、見せたい部分を切り抜いて
キャプションを載せた1枚にする。

デバイスフレームは描かない。
**Google Play はデバイス画像の使用を禁止している**ため、
フレームを使わない作りにしておけば両ストアで同じ素材方針が使える。

### 使い方

引数なしで実行すると、ストアが要求するサイズの一覧が出る。

```bash
swift tools/compose.swift
```

基本形:

```bash
swift tools/compose.swift --in <元画像>.png --out <出力>.png \
  --title "1行目" --sub "2行目" \
  --crop "0.0,0.13,1.0,0.56" --scale 1.0 --accent "#FF9D55"
```

2枚を並べる（配色の比較など、1枚では伝わらないもの）:

```bash
swift tools/compose.swift --in <左/上>.png --in2 <右/下>.png --out <出力>.png \
  --title "2つの配色に対応" --sub "SV / 旧HOME を切り替え" \
  --labels "SV,旧HOME" --stack 1 \
  --crop "0.03,0.178,0.94,0.32" --scale 0.90 --accent "#79C64B"
```

### 主なオプション

| オプション | 既定 | 内容 |
|-----------|------|------|
| `--crop x,y,w,h` | 全体 | 元画像に対する割合(0-1)で切り抜く |
| `--scale` | 0.82 | 出力幅に対する配置幅の割合 |
| `--accent` | オレンジ | キャプション下の線の色 |
| `--width` / `--height` | 1320 / 2868 | 出力サイズ |
| `--bg` | 暗い紫〜青緑 | 背景グラデーション（`"#RRGGBB,#RRGGBB"`） |
| `--in2` | なし | 2枚目。渡すと横に並べる |
| `--stack` | なし | 2枚を横ではなく上下に並べる |
| `--labels` | なし | 2枚並べたときの見出し（`"左,右"`） |

**アプリごとに `--bg` を変えること。** 既定のままだと、
どのアプリも同じ暗い紫背景になり、並べたときに同じ人が作ったものだと分かる。

文字サイズや余白は 1320 幅を基準にした比率で追従するので、
`--width` / `--height` を変えてもレイアウトは崩れない。

### 横に並べるか、上下に並べるか

横に並べると1枚あたりの幅が半分になる。
ホイールのように横幅をいっぱいに使う画面だと縦が余って間延びするので、
その場合は `--stack` で上下に並べる。
