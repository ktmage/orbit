# Orbit

Orbitは、MoonBitのアプリケーションをプラグインに分けて組み合わせるライブラリです。必要なサービスが揃ってからプラグインを起動し、設定の変更や実装の交換では、関係する処理の終了を待ってから起動し直します。

Cordisの構成原理を参考にしています。Perilune固有の型や処理は含まず、AIモデルを使わないアプリケーションにも組み込めます。

## できること

- 同じプラグインを、設定と状態を分けて複数登録する。
- サービスを型付きキーで提供・取得し、用途ごとのスコープで提供元を分ける。
- イベントに登録した関数を順次または並行して呼ぶ。途中で打ち切ったり、前後に処理を追加したりできる。
- 通信などの非同期処理に中断を求め、実際の終了と、ファイルを閉じるなどの終了処理を待つ。
- 終了処理に失敗した場合は、完了済みの関数を繰り返さず、残った処理と中断した変更を再開する。
- プラグインの状態、必要なサービス、エラー、変更要求の結果を調べる。

JavaScriptではNode.js、WebAssemblyではMoonBit付属の`moonrun`を使い、同じテストを実行します。外部コードの動的な読み込み、HMR、既存のTypeScriptプラグインとの互換性は含みません。

## 動かす

MoonBit、Node.js、Pythonのバージョンと導入方法は[mise.toml](mise.toml)で管理します。設定はmacOSのApple Silicon向けです。Perilune直下の`mise.toml`も、このファイルを参照します。

Orbitのディレクトリで実行します。

```sh
mise trust
mise install
mise exec -- moon update
mise exec -- moon run examples/clock --target js
mise exec -- moon run examples/clock --target wasm
```

[時計の例](examples/clock/main.mbt)は、サービスを使う画面表示を先に登録します。時計を追加すると`12:00`を表示します。設定を変更すると画面表示も起動し直し、時刻が`13:00`に変わります。最後にランタイムの終了を待ちます。

使うパッケージは[例のmoon.pkg](examples/clock/moon.pkg)にあります。プラグインとランタイムは`core/runtime`、サービスキーは`core/service`、イベントキーは`core/event`から読み込みます。`adapters/async_driver`は非同期処理の開始と中断をMoonBitのタスクグループへ接続します。

## 検証する

Orbitのディレクトリで実行します。CIも同じコマンドを使います。共通の検査に続けて、指定したターゲットのテストと時計の例を実行します。検査内容は[check_ci.py](tools/check_ci.py)で管理します。

```sh
mise exec -- python3 tools/check_ci.py --target js
mise exec -- python3 tools/check_ci.py --target wasm
```

[GitHub Actionsの設定](.github/workflows/ci.yml)は、pushとプルリクエストでJS・Wasmを別々に検査します。手動でも実行できます。ローカルの文書や個人の設定は必要ありません。

テストでは、予定した件数と完了した件数を照合します。型の検査では、正しい対照コードを先にコンパイルし、不正なコードが想定した箇所と理由で拒否されることを確かめます。

[操作順序のテスト](tests/sequences/)は、更新や登録解除など、終了処理と重なる要求の順序を生成します。最初に要求する変更と、終了処理の失敗回数も変え、終了前に成功を返さないこと、依存先を使い終わるまで保持すること、無関係なプラグインを停止しないことを検証します。失敗時には順序と条件を表示し、同じコマンドで再現できます。

性能の測定は別に実行します。

```sh
mise exec -- python3 tools/measure_runtime.py --output /tmp/orbit-measurement.json
```

測定結果には、登録、イベントの呼び出し、交換、停止の時間とメモリ量を記録します。JavaScriptはGC後のヒープ使用量、WebAssemblyは確保した線形メモリの容量です。両者を同じ種類の使用量として比較するものではありません。

## コードを読む

| 場所 | 担当 |
| --- | --- |
| [core/runtime](core/runtime/) | 登録・変更の受付、起動と停止の進行、状態の取得 |
| [core/dependency](core/dependency/) | サービスの提供元を探し、停止する順序を求める |
| [core/service](core/service/) | 型を保って値と参照を保持する |
| [core/lifecycle](core/lifecycle/) | タスクの中断、終了待ち、終了関数の実行 |
| [core/event](core/event/) | イベントの登録と、方式ごとの呼び出し |
| [core/identity](core/identity/) | 対象ごとに型を分けた識別子 |
| [tests/integration](tests/integration/) | 公開APIを組み合わせた振る舞いの検証 |
| [tests/sequences](tests/sequences/) | 操作順序と失敗の条件を生成した検証 |

各パッケージの`pkg.generated.mbti`が公開APIの一覧です。通信、ファイル操作、設定や秘密情報の保存は、組み込むアプリケーションが実装します。Orbit自体が設定や診断情報を外部へ送信することはありません。
