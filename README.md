fgdconvert
==========

FGD to Vector Tiles converter on Hadoop
基盤地図情報ベクトルタイルコンバータ（Hadoop 使用）

1. このレポジトリをクローンする
2. 基盤地図情報をダウンロードし、ZIPファイルのまま置いておく。
3. convert.rbに2.のファイル置き場を書き、また input フォルダを作成する
4. rake

※hadoopを使うので、ディスクをかなり必要とする。

※特にDEMについて、おそらく変換に問題がある場合がある。今後修正。
