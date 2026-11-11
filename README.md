# Orbit

[![CI](https://github.com/ktmage/orbit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ktmage/orbit/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) ![Status: Experimental](https://img.shields.io/badge/Status-Experimental-orange.svg)

Orbitは、CordisのContext ParadigmをMoonBitで実装するプラグイン基盤です。操作と取り消しをコンテキストへ登録し、宣言した依存関係に合わせて起動・停止します。

> [!WARNING]
> Orbitは実験段階のライブラリです。機能やドキュメントの整備が追いつかない場合があります。APIの安定性、セキュリティ上の安全性、継続的な保守は保証していません。

プラグインがほかのプラグインへ公開する関数や値を、サービスとして扱います。Orbitは必要なサービスが揃うまで起動を待ち、設定や実装が変更されたときは、そのサービスを使うプラグインも停止してから起動し直します。

「CordisのMoonBit版」として、[論文](https://arxiv.org/pdf/2608.25512v1)にある可逆な副作用、反応的な依存関係、コンテキストを通した合成を採用しています。API互換性は対象に含めません。特定のアプリケーションに依存せず、コマンドラインツールやデスクトップアプリケーションなどに組み込めます。

## 主な機能

- 同じプラグインを複数登録し、それぞれ異なる設定と状態で使用できます。
- サービスを型付きのキーで識別し、関数や値をほかのプラグインから取得できます。
- `ctx.with_effect`で操作を入れ子にまとめ、`EffectHandle.dispose()`でその操作だけを取り消せます。タスク、資源、購読、子プラグインをまとめて回収できます。
- `scope.child()`で寿命をまとめ、`scope.isolate(key.realm())`でキーごとの参照先を分けます。同じ領域を渡せば、兄弟スコープでも提供元を共有できます。
- `scope.intercept`でサービスの利用条件を指定できます。サービス独自の操作も、`ServiceContext.effect`で呼び出し元の寿命に結び付けられます。
- イベントを送ると、受信する関数を順番に、または並行して呼び出せます。途中で呼び出しを打ち切る方式や、各関数が次の処理を呼ぶ方式も選べます。
- プラグインの停止時に、通信などの非同期処理へ中断を求めます。実際に処理が終わり、ファイルを閉じるなどの終了処理が完了するまで待ちます。
- 終了処理に失敗した場合は、失敗した箇所から再試行できます。既に完了した処理は繰り返さず、停止していた設定の更新や登録解除を続けます。
- 宣言した構成をローダーへ渡すと、安定したIDを使って差分を適用します。変更のない実行は維持し、適用に失敗した場合は前の構成の復元を試みます。
- プラグインの状態、参照しているサービス、エラー、設定変更などの結果を取得できます。

コードの読み込みは、ホストが`Resolver`へ実装します。`Loader.reload`は全定義の準備後に交換し、読み込み失敗では現在の構成を維持します。ファイル監視や任意のJS／Wasmバイナリーの読み込みは同梱していません。

取り消しが元の変更を回収することと、独立した操作の順序を交換できることは、サービス作者の契約です。Orbitはその取り消しの保持と実行を管理します。外部へ送信済みのデータや、管理外の共有状態を自動で巻き戻すものではありません。順序に意味があるイベントでは、優先度とインスタンスの登録順を再起動後も維持します。

## 対応環境

JavaScriptとWebAssemblyへのコンパイルに対応しています。テストは、JavaScriptではNode.js、WebAssemblyではMoonBit付属の`moonrun`で実行します。

## 開発環境の準備

[mise.toml](mise.toml)に、MoonBit、Node.js、Pythonなどのバージョンとインストール方法を定めています。この設定とCIは、Apple Siliconを搭載したmacOSを対象にしています。

[mise](https://mise.jdx.dev/getting-started.html)をインストールした環境で、リポジトリを取得して開発環境を準備します。

```sh
git clone git@github.com:ktmage/orbit.git
cd orbit
mise trust
mise install
mise exec -- moon update
```

## サンプルの実行

[時計サービスのサンプル](examples/clock/main.mbt)では、時刻を提供するプラグインと、その時刻を端末に出力するプラグインを登録します。

```sh
mise exec -- moon run examples/clock --target js
mise exec -- moon run examples/clock --target wasm
```

どちらのコマンドも、次の結果を出力します。

```text
12:00
13:00
```

出力するプラグインを先に登録しても、時計サービスが登録されるまで起動を待ちます。時計を登録すると`12:00`を出力し、設定を変更すると起動し直して`13:00`を出力します。最後に、登録したプラグインをすべて終了します。

必要なパッケージの指定は、サンプルの[moon.pkg](examples/clock/moon.pkg)を参照してください。プラグインの登録や終了を管理する`Runtime`は`core/runtime`、サービスを識別する`ServiceKey`は`core/service`から読み込みます。`adapters/async_driver`は、Orbitが要求した非同期処理の開始と中断を、MoonBitのタスクグループで実行します。

[リビジョン更新のサンプル](examples/reload/main.mbt)では、同じ構成の再適用で再起動せず、リビジョンを変えたときだけサービスと利用側を更新します。用意済みの定義からリビジョンを選ぶResolverで、JSとWasm共通の更新経路を示します。

```sh
mise exec -- moon run examples/reload --target js
mise exec -- moon run examples/reload --target wasm
```

出力はどちらも`v1`、`v2`の2行です。[コマンドレジストリ](extensions/commands/commands.mbt)は、本体を変更せず、サービス経由で登録した操作を利用側の停止時に取り消す拡張例です。

`child()`は参照先を分けません。以前の親へのフォールバックが必要なコードは`shadow()`へ、厳密に分離するコードは`isolate()`へ移行します。イベントの通知先を分ける場合は`isolate_events()`を使います。

## テストと静的検査

Orbitリポジトリのルートディレクトリから、次のコマンドを実行してください。CIでも同じコマンドを使います。

```sh
mise exec -- python3 tools/check_ci.py --target js
mise exec -- python3 tools/check_ci.py --target wasm
```

[check_ci.py](tools/check_ci.py)は、整形とワークフローの構文を検査し、検証ツール自体のテストを実行します。その後、パッケージ間の依存方向を調べ、指定した実行環境でOrbitのテストとサンプルを実行します。

テストの種類と、そこで確かめる内容は次のとおりです。

| テスト | 確かめる内容 |
| --- | --- |
| 各パッケージのテスト | 個々の機能が期待する結果を返すこと |
| [公開APIを組み合わせるテスト](tests/integration/) | 登録、設定の変更、停止などを続けて行ったときの動作 |
| [操作順序を生成するテスト](tests/sequences/) | 終了処理を待つ間に更新や解除が重なっても、処理の終了を待ち、関係のないプラグインを止めないこと |
| [型の誤用を検出するテスト](tests/compile_fail/) | 誤った型や公開されていないフィールドを使うコードを、コンパイラーが拒否すること |

テストは、予定した件数と完了した件数を照合します。型の誤用を検出するテストでは、正しく使ったコードを先にコンパイルします。その上で、誤ったコードが想定した箇所と理由で拒否されることを確認します。

[GitHub Actions](.github/workflows/ci.yml)では、コードをpushしたときや、プルリクエストを作成・更新したときに検査します。JavaScriptとWebAssemblyを別々のジョブで実行し、それぞれの結果を確認できます。手動実行にも対応しています。

## ソースコードの構成

| ディレクトリ | 役割 |
| --- | --- |
| [loader](loader/) | 宣言した構成を差分適用し、リビジョン更新と失敗時の復元を進める |
| [extensions/commands](extensions/commands/) | 可逆なコマンド登録をサービスとして提供する |
| [core/runtime](core/runtime/) | プラグインの登録や変更を受け付け、起動・停止を進める |
| [core/dependency](core/dependency/) | サービスの提供元を探し、依存関係から停止する順序を決める |
| [core/service](core/service/) | サービスの値を保持し、型に合った参照を返す |
| [core/lifecycle](core/lifecycle/) | 非同期処理へ中断を求め、完了を待って終了処理を実行する |
| [core/event](core/event/) | イベントを受信する関数を登録し、指定した方式で呼び出す |
| [core/identity](core/identity/) | プラグインや操作などを区別する識別子を発行する |
| [adapters/async_driver](adapters/async_driver/) | MoonBitのタスクグループを使って非同期処理を実行する |

各パッケージの`pkg.generated.mbti`に、公開する型と関数の一覧があります。

通信やファイル操作、設定の保存は、Orbitを組み込むアプリケーションが実装します。Orbit自体が設定や診断情報を外部へ送信することはありません。

## ライセンス

[MIT License](LICENSE)。著作権者はktmageです。
