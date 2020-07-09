# ツールチェーン共通スクリプト

このリポジトリではツールチェーンおよびパイプランでで使用される共通のスクリプトを管理しています。

独自のツールチェーンこれらのスクリプトをを利用する方法は様々ありますが、そのいくつかをいかに例示します。

1. スクリプトの内容をパイプラインのジョブに直接コピー

2. パイプラインのジョブでリポジトリをクローンしてシェルを実行

3. スクリプトをソースコードのリポジトリのサブフォルダにコピーして、パイプラインのジョブで実行

### 推奨事項:
1. まずはじめに、`set -x` をスクリプトの先頭に追記し、スクリプトのコマンド実行の詳細を確認んすることでスクリプトの挙動について理解することをお薦めします。
2. `sh`コマンドではなく`source`コマンドでスクリプトを起動することで親のシェル環境でスクリプトを実行しましょう。このようにすることで、同一ステージ内の後続のジョブにてスクリプトがexportした環境変数を使用することが可能になります。