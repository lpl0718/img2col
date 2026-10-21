卷积算子采用切片im2col算法实现
不考虑硬件资源的条件下支持，任意BHWC的特征图输入，矩形或者非矩形卷积核心，步长卷积，空洞卷积
切片大小可配置
逐输出通道的bias和反量化scale


量化工具 https://github.com/OpenPPL/ppq