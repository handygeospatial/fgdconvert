fgdconvert
==========

FGD to Vector Tiles converter on Hadoop
基盤地図情報ベクトルタイルコンバータ（Hadoop 使用）

1. このレポジトリをクローンする
2. source フォルダに基盤地図情報をXMLに展開し、ファイルごとにgz圧縮しておく
3. input フォルダを作成する
4. rake

※hadoopを使うので、ディスクをかなり必要とする。

※特にDEMについて、おそらく変換に問題がある場合がある。今後修正。
