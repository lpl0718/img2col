// ============================================================
// Vivado Testbench for op_convolution_full IP (int8 中维度验证)
// 测试: 1x90x160x8 int8 ifm + 8x8x3x3 int8 weight
// 目的: 验证 8 输入/输出通道、90x160 中尺寸的卷积功能
//
// 数据类型 (与 conv_types.h 一致):
//   ifm/weight: int8 (ap_int<8>)
//   bias/deq:   int32 (ap_int<32>)
//   ofm:        int8 (ap_int<8>), 已做 [0,127] 截断
//
// 数据布局:
//   ifm: BHWC = (1, 90, 160, 8), 每元素 1 字节
//   weight: (oc=8, ic=8, kh=3, kw=3), 每元素 1 字节
//   bias: (8,), 4 字节 each
//   deq:  (8,), 4 字节 each
//   ofm:  BHWC = (1, 90, 160, 8), 每元素 1 字节
// ============================================================

`timescale 1ns / 1ps

module tb_op_conv_int8_8ch_90x160;

    // ==================== 维度常量 ====================
    localparam BATCH = 1;
    localparam IN_H  = 90;
    localparam IN_W  = 160;
    localparam IN_C  = 8;  // 8 输入通道
    localparam OUT_C = 8;  // 8 输出通道
    localparam KH    = 3;
    localparam KW    = 3;
    localparam STRIDE_H = 1;
    localparam STRIDE_W = 1;
    localparam PAD_H    = 1;
    localparam PAD_W    = 1;
    localparam DIL_H    = 1;
    localparam DIL_W    = 1;
    // out_h = (90 + 2*1 - 1*2)/1 + 1 = 90
    // out_w = (160 + 2*1 - 1*2)/1 + 1 = 160
    localparam OUT_H = 90;
    localparam OUT_W = 160;

    // ==================== 元素总数 ====================
    localparam IFM_SIZE  = BATCH * IN_H * IN_W * IN_C;   // 1*90*160*8 = 115200
    localparam WGT_SIZE  = OUT_C * IN_C * KH * KW;        // 8*8*3*3 = 576
    localparam BIAS_SIZE = OUT_C;                          // 8
    localparam DEQ_SIZE  = OUT_C;                          // 8
    localparam OFM_SIZE  = BATCH * OUT_H * OUT_W * OUT_C; // 1*90*160*8 = 115200

    // ==================== 时钟/复位 ====================
    reg ap_clk   = 0;
    reg ap_rst_n = 0;
    always #5 ap_clk = ~ap_clk;  // 100 MHz

    // ==================== 控制寄存器地址 ====================
    localparam [7:0]
        ADDR_AP_CTRL   = 8'h00,
        ADDR_PARAMS    = 8'h10,
        ADDR_IFM       = 8'h70,
        ADDR_WEIGHT    = 8'h7c,
        ADDR_BIAS      = 8'h88,
        ADDR_DEQ       = 8'h94,
        ADDR_OFM       = 8'ha0,
        ADDR_ZERO_PT   = 8'hac,
        ADDR_QT_EN     = 8'hb4,
        ADDR_QT_SCALE  = 8'hbc,
        ADDR_QT_OFFSET = 8'hc4;

    // ============================================================
    // gmem0 (ifm) 信号
    // ============================================================
    wire        g0_AWVALID, g0_AWREADY, g0_WVALID, g0_WREADY, g0_WLAST;
    wire [63:0] g0_AWADDR;
    wire [0:0]  g0_AWID, g0_WID, g0_BID, g0_RID;
    wire [7:0]  g0_AWLEN, g0_ARLEN;
    wire [2:0]  g0_AWSIZE, g0_ARSIZE;
    wire [1:0]  g0_AWBURST, g0_AWLOCK, g0_ARBURST, g0_ARLOCK, g0_BRESP, g0_RRESP;
    wire [3:0]  g0_AWCACHE, g0_AWQOS, g0_AWREGION, g0_ARCACHE, g0_ARQOS, g0_ARREGION;
    wire [2:0]  g0_AWPROT, g0_ARPROT;
    wire [0:0]  g0_AWUSER, g0_WUSER, g0_BUSER, g0_ARUSER, g0_RUSER;
    wire [31:0] g0_WDATA, g0_RDATA;
    wire [3:0]  g0_WSTRB;
    wire        g0_BVALID, g0_BREADY;
    wire        g0_ARVALID, g0_ARREADY;
    wire [63:0] g0_ARADDR;
    wire        g0_RVALID, g0_RREADY, g0_RLAST;

    // gmem1 (weight) 信号
    wire        g1_AWVALID, g1_AWREADY, g1_WVALID, g1_WREADY, g1_WLAST;
    wire [63:0] g1_AWADDR;
    wire [0:0]  g1_AWID, g1_WID, g1_BID, g1_RID;
    wire [7:0]  g1_AWLEN, g1_ARLEN;
    wire [2:0]  g1_AWSIZE, g1_ARSIZE;
    wire [1:0]  g1_AWBURST, g1_AWLOCK, g1_ARBURST, g1_ARLOCK, g1_BRESP, g1_RRESP;
    wire [3:0]  g1_AWCACHE, g1_AWQOS, g1_AWREGION, g1_ARCACHE, g1_ARQOS, g1_ARREGION;
    wire [2:0]  g1_AWPROT, g1_ARPROT;
    wire [0:0]  g1_AWUSER, g1_WUSER, g1_BUSER, g1_ARUSER, g1_RUSER;
    wire [31:0] g1_WDATA, g1_RDATA;
    wire [3:0]  g1_WSTRB;
    wire        g1_BVALID, g1_BREADY;
    wire        g1_ARVALID, g1_ARREADY;
    wire [63:0] g1_ARADDR;
    wire        g1_RVALID, g1_RREADY, g1_RLAST;

    // gmem2 (bias) 信号
    wire        g2_AWVALID, g2_AWREADY, g2_WVALID, g2_WREADY, g2_WLAST;
    wire [63:0] g2_AWADDR;
    wire [0:0]  g2_AWID, g2_WID, g2_BID, g2_RID;
    wire [7:0]  g2_AWLEN, g2_ARLEN;
    wire [2:0]  g2_AWSIZE, g2_ARSIZE;
    wire [1:0]  g2_AWBURST, g2_AWLOCK, g2_ARBURST, g2_ARLOCK, g2_BRESP, g2_RRESP;
    wire [3:0]  g2_AWCACHE, g2_AWQOS, g2_AWREGION, g2_ARCACHE, g2_ARQOS, g2_ARREGION;
    wire [2:0]  g2_AWPROT, g2_ARPROT;
    wire [0:0]  g2_AWUSER, g2_WUSER, g2_BUSER, g2_ARUSER, g2_RUSER;
    wire [31:0] g2_WDATA, g2_RDATA;
    wire [3:0]  g2_WSTRB;
    wire        g2_BVALID, g2_BREADY;
    wire        g2_ARVALID, g2_ARREADY;
    wire [63:0] g2_ARADDR;
    wire        g2_RVALID, g2_RREADY, g2_RLAST;

    // gmem3 (deq) 信号
    wire        g3_AWVALID, g3_AWREADY, g3_WVALID, g3_WREADY, g3_WLAST;
    wire [63:0] g3_AWADDR;
    wire [0:0]  g3_AWID, g3_WID, g3_BID, g3_RID;
    wire [7:0]  g3_AWLEN, g3_ARLEN;
    wire [2:0]  g3_AWSIZE, g3_ARSIZE;
    wire [1:0]  g3_AWBURST, g3_AWLOCK, g3_ARBURST, g3_ARLOCK, g3_BRESP, g3_RRESP;
    wire [3:0]  g3_AWCACHE, g3_AWQOS, g3_AWREGION, g3_ARCACHE, g3_ARQOS, g3_ARREGION;
    wire [2:0]  g3_AWPROT, g3_ARPROT;
    wire [0:0]  g3_AWUSER, g3_WUSER, g3_BUSER, g3_ARUSER, g3_RUSER;
    wire [31:0] g3_WDATA, g3_RDATA;
    wire [3:0]  g3_WSTRB;
    wire        g3_BVALID, g3_BREADY;
    wire        g3_ARVALID, g3_ARREADY;
    wire [63:0] g3_ARADDR;
    wire        g3_RVALID, g3_RREADY, g3_RLAST;

    // gmem4 (ofm) 信号
    wire        g4_AWVALID, g4_AWREADY, g4_WVALID, g4_WREADY, g4_WLAST;
    wire [63:0] g4_AWADDR;
    wire [0:0]  g4_AWID, g4_WID, g4_BID, g4_RID;
    wire [7:0]  g4_AWLEN, g4_ARLEN;
    wire [2:0]  g4_AWSIZE, g4_ARSIZE;
    wire [1:0]  g4_AWBURST, g4_AWLOCK, g4_ARBURST, g4_ARLOCK, g4_BRESP, g4_RRESP;
    wire [3:0]  g4_AWCACHE, g4_AWQOS, g4_AWREGION, g4_ARCACHE, g4_ARQOS, g4_ARREGION;
    wire [2:0]  g4_AWPROT, g4_ARPROT;
    wire [0:0]  g4_AWUSER, g4_WUSER, g4_BUSER, g4_ARUSER, g4_RUSER;
    wire [31:0] g4_WDATA, g4_RDATA;
    wire [3:0]  g4_WSTRB;
    wire        g4_BVALID, g4_BREADY;
    wire        g4_ARVALID, g4_ARREADY;
    wire [63:0] g4_ARADDR;
    wire        g4_RVALID, g4_RREADY, g4_RLAST;

    // s_axi_control 信号
    wire        c_AWVALID, c_AWREADY, c_WVALID, c_WREADY;
    wire [7:0]  c_AWADDR, c_ARADDR;
    wire [31:0] c_WDATA, c_RDATA;
    wire [3:0]  c_WSTRB;
    wire        c_BVALID, c_BREADY;
    wire [1:0]  c_BRESP, c_RRESP;
    wire        c_ARVALID, c_ARREADY;
    wire        c_RVALID, c_RREADY;
    wire        interrupt;

    // ============================================================
    // DUT 例化
    // ============================================================
    op_convolution_full dut (
        .ap_clk(ap_clk), .ap_rst_n(ap_rst_n),
        // gmem0
        .m_axi_gmem0_AWVALID(g0_AWVALID), .m_axi_gmem0_AWREADY(g0_AWREADY),
        .m_axi_gmem0_AWADDR(g0_AWADDR),   .m_axi_gmem0_AWID(g0_AWID),
        .m_axi_gmem0_AWLEN(g0_AWLEN),     .m_axi_gmem0_AWSIZE(g0_AWSIZE),
        .m_axi_gmem0_AWBURST(g0_AWBURST), .m_axi_gmem0_AWLOCK(g0_AWLOCK),
        .m_axi_gmem0_AWCACHE(g0_AWCACHE), .m_axi_gmem0_AWPROT(g0_AWPROT),
        .m_axi_gmem0_AWQOS(g0_AWQOS),     .m_axi_gmem0_AWREGION(g0_AWREGION),
        .m_axi_gmem0_AWUSER(g0_AWUSER),
        .m_axi_gmem0_WVALID(g0_WVALID),   .m_axi_gmem0_WREADY(g0_WREADY),
        .m_axi_gmem0_WDATA(g0_WDATA),     .m_axi_gmem0_WSTRB(g0_WSTRB),
        .m_axi_gmem0_WLAST(g0_WLAST),     .m_axi_gmem0_WID(g0_WID),
        .m_axi_gmem0_WUSER(g0_WUSER),
        .m_axi_gmem0_BVALID(g0_BVALID),   .m_axi_gmem0_BREADY(g0_BREADY),
        .m_axi_gmem0_BRESP(g0_BRESP),     .m_axi_gmem0_BID(g0_BID),
        .m_axi_gmem0_BUSER(g0_BUSER),
        .m_axi_gmem0_ARVALID(g0_ARVALID), .m_axi_gmem0_ARREADY(g0_ARREADY),
        .m_axi_gmem0_ARADDR(g0_ARADDR),   .m_axi_gmem0_ARID(g0_ARID),
        .m_axi_gmem0_ARLEN(g0_ARLEN),     .m_axi_gmem0_ARSIZE(g0_ARSIZE),
        .m_axi_gmem0_ARBURST(g0_ARBURST), .m_axi_gmem0_ARLOCK(g0_ARLOCK),
        .m_axi_gmem0_ARCACHE(g0_ARCACHE), .m_axi_gmem0_ARPROT(g0_ARPROT),
        .m_axi_gmem0_ARQOS(g0_ARQOS),     .m_axi_gmem0_ARREGION(g0_ARREGION),
        .m_axi_gmem0_ARUSER(g0_ARUSER),
        .m_axi_gmem0_RVALID(g0_RVALID),   .m_axi_gmem0_RREADY(g0_RREADY),
        .m_axi_gmem0_RDATA(g0_RDATA),     .m_axi_gmem0_RLAST(g0_RLAST),
        .m_axi_gmem0_RID(g0_RID),         .m_axi_gmem0_RUSER(g0_RUSER),
        .m_axi_gmem0_RRESP(g0_RRESP),
        // gmem1
        .m_axi_gmem1_AWVALID(g1_AWVALID), .m_axi_gmem1_AWREADY(g1_AWREADY),
        .m_axi_gmem1_AWADDR(g1_AWADDR),   .m_axi_gmem1_AWID(g1_AWID),
        .m_axi_gmem1_AWLEN(g1_AWLEN),     .m_axi_gmem1_AWSIZE(g1_AWSIZE),
        .m_axi_gmem1_AWBURST(g1_AWBURST), .m_axi_gmem1_AWLOCK(g1_AWLOCK),
        .m_axi_gmem1_AWCACHE(g1_AWCACHE), .m_axi_gmem1_AWPROT(g1_AWPROT),
        .m_axi_gmem1_AWQOS(g1_AWQOS),     .m_axi_gmem1_AWREGION(g1_AWREGION),
        .m_axi_gmem1_AWUSER(g1_AWUSER),
        .m_axi_gmem1_WVALID(g1_WVALID),   .m_axi_gmem1_WREADY(g1_WREADY),
        .m_axi_gmem1_WDATA(g1_WDATA),     .m_axi_gmem1_WSTRB(g1_WSTRB),
        .m_axi_gmem1_WLAST(g1_WLAST),     .m_axi_gmem1_WID(g1_WID),
        .m_axi_gmem1_WUSER(g1_WUSER),
        .m_axi_gmem1_BVALID(g1_BVALID),   .m_axi_gmem1_BREADY(g1_BREADY),
        .m_axi_gmem1_BRESP(g1_BRESP),     .m_axi_gmem1_BID(g1_BID),
        .m_axi_gmem1_BUSER(g1_BUSER),
        .m_axi_gmem1_ARVALID(g1_ARVALID), .m_axi_gmem1_ARREADY(g1_ARREADY),
        .m_axi_gmem1_ARADDR(g1_ARADDR),   .m_axi_gmem1_ARID(g1_ARID),
        .m_axi_gmem1_ARLEN(g1_ARLEN),     .m_axi_gmem1_ARSIZE(g1_ARSIZE),
        .m_axi_gmem1_ARBURST(g1_ARBURST), .m_axi_gmem1_ARLOCK(g1_ARBURST),
        .m_axi_gmem1_ARCACHE(g1_ARCACHE), .m_axi_gmem1_ARPROT(g1_ARPROT),
        .m_axi_gmem1_ARQOS(g1_ARQOS),     .m_axi_gmem1_ARREGION(g1_ARREGION),
        .m_axi_gmem1_ARUSER(g1_ARUSER),
        .m_axi_gmem1_RVALID(g1_RVALID),   .m_axi_gmem1_RREADY(g1_RREADY),
        .m_axi_gmem1_RDATA(g1_RDATA),     .m_axi_gmem1_RLAST(g1_RLAST),
        .m_axi_gmem1_RID(g1_RID),         .m_axi_gmem1_RUSER(g1_RUSER),
        .m_axi_gmem1_RRESP(g1_RRESP),
        // gmem2
        .m_axi_gmem2_AWVALID(g2_AWVALID), .m_axi_gmem2_AWREADY(g2_AWREADY),
        .m_axi_gmem2_AWADDR(g2_AWADDR),   .m_axi_gmem2_AWID(g2_AWID),
        .m_axi_gmem2_AWLEN(g2_AWLEN),     .m_axi_gmem2_AWSIZE(g2_AWSIZE),
        .m_axi_gmem2_AWBURST(g2_AWBURST), .m_axi_gmem2_AWLOCK(g2_AWLOCK),
        .m_axi_gmem2_AWCACHE(g2_AWCACHE), .m_axi_gmem2_AWPROT(g2_AWPROT),
        .m_axi_gmem2_AWQOS(g2_AWQOS),     .m_axi_gmem2_AWREGION(g2_AWREGION),
        .m_axi_gmem2_AWUSER(g2_AWUSER),
        .m_axi_gmem2_WVALID(g2_WVALID),   .m_axi_gmem2_WREADY(g2_WREADY),
        .m_axi_gmem2_WDATA(g2_WDATA),     .m_axi_gmem2_WSTRB(g2_WSTRB),
        .m_axi_gmem2_WLAST(g2_WLAST),     .m_axi_gmem2_WID(g2_WID),
        .m_axi_gmem2_WUSER(g2_WUSER),
        .m_axi_gmem2_BVALID(g2_BVALID),   .m_axi_gmem2_BREADY(g2_BREADY),
        .m_axi_gmem2_BRESP(g2_BRESP),     .m_axi_gmem2_BID(g2_BID),
        .m_axi_gmem2_BUSER(g2_BUSER),
        .m_axi_gmem2_ARVALID(g2_ARVALID), .m_axi_gmem2_ARREADY(g2_ARREADY),
        .m_axi_gmem2_ARADDR(g2_ARADDR),   .m_axi_gmem2_ARID(g2_ARID),
        .m_axi_gmem2_ARLEN(g2_ARLEN),     .m_axi_gmem2_ARSIZE(g2_ARSIZE),
        .m_axi_gmem2_ARBURST(g2_ARBURST), .m_axi_gmem2_ARLOCK(g2_ARBURST),
        .m_axi_gmem2_ARCACHE(g2_ARCACHE), .m_axi_gmem2_ARPROT(g2_ARPROT),
        .m_axi_gmem2_ARQOS(g2_ARQOS),     .m_axi_gmem2_ARREGION(g2_ARREGION),
        .m_axi_gmem2_ARUSER(g2_ARUSER),
        .m_axi_gmem2_RVALID(g2_RVALID),   .m_axi_gmem2_RREADY(g2_RREADY),
        .m_axi_gmem2_RDATA(g2_RDATA),     .m_axi_gmem2_RLAST(g2_RLAST),
        .m_axi_gmem2_RID(g2_RID),         .m_axi_gmem2_RUSER(g2_RUSER),
        .m_axi_gmem2_RRESP(g2_RRESP),
        // gmem3
        .m_axi_gmem3_AWVALID(g3_AWVALID), .m_axi_gmem3_AWREADY(g3_AWREADY),
        .m_axi_gmem3_AWADDR(g3_AWADDR),   .m_axi_gmem3_AWID(g3_AWID),
        .m_axi_gmem3_AWLEN(g3_AWLEN),     .m_axi_gmem3_AWSIZE(g3_AWSIZE),
        .m_axi_gmem3_AWBURST(g3_AWBURST), .m_axi_gmem3_AWLOCK(g3_AWLOCK),
        .m_axi_gmem3_AWCACHE(g3_AWCACHE), .m_axi_gmem3_AWPROT(g3_AWPROT),
        .m_axi_gmem3_AWQOS(g3_AWQOS),     .m_axi_gmem3_AWREGION(g3_AWREGION),
        .m_axi_gmem3_AWUSER(g3_AWUSER),
        .m_axi_gmem3_WVALID(g3_WVALID),   .m_axi_gmem3_WREADY(g3_WREADY),
        .m_axi_gmem3_WDATA(g3_WDATA),     .m_axi_gmem3_WSTRB(g3_WSTRB),
        .m_axi_gmem3_WLAST(g3_WLAST),     .m_axi_gmem3_WID(g3_WID),
        .m_axi_gmem3_WUSER(g3_WUSER),
        .m_axi_gmem3_BVALID(g3_BVALID),   .m_axi_gmem3_BREADY(g3_BREADY),
        .m_axi_gmem3_BRESP(g3_BRESP),     .m_axi_gmem3_BID(g3_BID),
        .m_axi_gmem3_BUSER(g3_BUSER),
        .m_axi_gmem3_ARVALID(g3_ARVALID), .m_axi_gmem3_ARREADY(g3_ARREADY),
        .m_axi_gmem3_ARADDR(g3_ARADDR),   .m_axi_gmem3_ARID(g3_ARID),
        .m_axi_gmem3_ARLEN(g3_ARLEN),     .m_axi_gmem3_ARSIZE(g3_ARSIZE),
        .m_axi_gmem3_ARBURST(g3_ARBURST), .m_axi_gmem3_ARLOCK(g3_ARLOCK),
        .m_axi_gmem3_ARCACHE(g3_ARCACHE), .m_axi_gmem3_ARPROT(g3_ARPROT),
        .m_axi_gmem3_ARQOS(g3_ARQOS),     .m_axi_gmem3_ARREGION(g3_ARREGION),
        .m_axi_gmem3_ARUSER(g3_ARUSER),
        .m_axi_gmem3_RVALID(g3_RVALID),   .m_axi_gmem3_RREADY(g3_RREADY),
        .m_axi_gmem3_RDATA(g3_RDATA),     .m_axi_gmem3_RLAST(g3_RLAST),
        .m_axi_gmem3_RID(g3_RID),         .m_axi_gmem3_RUSER(g3_RUSER),
        .m_axi_gmem3_RRESP(g3_RRESP),
        // gmem4
        .m_axi_gmem4_AWVALID(g4_AWVALID), .m_axi_gmem4_AWREADY(g4_AWREADY),
        .m_axi_gmem4_AWADDR(g4_AWADDR),   .m_axi_gmem4_AWID(g4_AWID),
        .m_axi_gmem4_AWLEN(g4_AWLEN),     .m_axi_gmem4_AWSIZE(g4_AWSIZE),
        .m_axi_gmem4_AWBURST(g4_AWBURST), .m_axi_gmem4_AWLOCK(g4_AWLOCK),
        .m_axi_gmem4_AWCACHE(g4_AWCACHE), .m_axi_gmem4_AWPROT(g4_AWPROT),
        .m_axi_gmem4_AWQOS(g4_AWQOS),     .m_axi_gmem4_AWREGION(g4_AWREGION),
        .m_axi_gmem4_AWUSER(g4_AWUSER),
        .m_axi_gmem4_WVALID(g4_WVALID),   .m_axi_gmem4_WREADY(g4_WREADY),
        .m_axi_gmem4_WDATA(g4_WDATA),     .m_axi_gmem4_WSTRB(g4_WSTRB),
        .m_axi_gmem4_WLAST(g4_WLAST),     .m_axi_gmem4_WID(g4_WID),
        .m_axi_gmem4_WUSER(g4_WUSER),
        .m_axi_gmem4_BVALID(g4_BVALID),   .m_axi_gmem4_BREADY(g4_BREADY),
        .m_axi_gmem4_BRESP(g4_BRESP),     .m_axi_gmem4_BID(g4_BID),
        .m_axi_gmem4_BUSER(g4_BUSER),
        .m_axi_gmem4_ARVALID(g4_ARVALID), .m_axi_gmem4_ARREADY(g4_ARREADY),
        .m_axi_gmem4_ARADDR(g4_ARADDR),   .m_axi_gmem4_ARID(g4_ARID),
        .m_axi_gmem4_ARLEN(g4_ARLEN),     .m_axi_gmem4_ARSIZE(g4_ARSIZE),
        .m_axi_gmem4_ARBURST(g4_ARBURST), .m_axi_gmem4_ARLOCK(g4_ARLOCK),
        .m_axi_gmem4_ARCACHE(g4_ARCACHE), .m_axi_gmem4_ARPROT(g4_ARPROT),
        .m_axi_gmem4_ARQOS(g4_ARQOS),     .m_axi_gmem4_ARREGION(g4_ARREGION),
        .m_axi_gmem4_ARUSER(g4_ARUSER),
        .m_axi_gmem4_RVALID(g4_RVALID),   .m_axi_gmem4_RREADY(g4_RREADY),
        .m_axi_gmem4_RDATA(g4_RDATA),     .m_axi_gmem4_RLAST(g4_RLAST),
        .m_axi_gmem4_RID(g4_RID),         .m_axi_gmem4_RUSER(g4_RUSER),
        .m_axi_gmem4_RRESP(g4_RRESP),
        // AXI-Lite control
        .s_axi_control_AWVALID(c_AWVALID), .s_axi_control_AWREADY(c_AWREADY),
        .s_axi_control_AWADDR(c_AWADDR),
        .s_axi_control_WVALID(c_WVALID), .s_axi_control_WREADY(c_WREADY),
        .s_axi_control_WDATA(c_WDATA), .s_axi_control_WSTRB(c_WSTRB),
        .s_axi_control_BVALID(c_BVALID), .s_axi_control_BREADY(c_BREADY),
        .s_axi_control_BRESP(c_BRESP),
        .s_axi_control_ARVALID(c_ARVALID), .s_axi_control_ARREADY(c_ARREADY),
        .s_axi_control_ARADDR(c_ARADDR),
        .s_axi_control_RVALID(c_RVALID), .s_axi_control_RREADY(c_RREADY),
        .s_axi_control_RDATA(c_RDATA), .s_axi_control_RRESP(c_RRESP),
        .interrupt()
    );

    // ============================================================
    // 5 个 axi_mem_model 实例 (gmem0-4)
    // ============================================================
    axi_mem_model #(
        .DATA_WIDTH(32), .ADDR_WIDTH(64), .ID_WIDTH(1),
        .USER_WIDTH(1), .MEM_SIZE(1048576)  // 1MB for ifm (115200 字节)
    ) gmem0_mem (
        .ap_clk(ap_clk), .ap_rst_n(ap_rst_n),
        .AWVALID(g0_AWVALID), .AWREADY(g0_AWREADY), .AWADDR(g0_AWADDR),
        .AWID(g0_AWID), .AWLEN(g0_AWLEN), .AWSIZE(g0_AWSIZE),
        .AWBURST(g0_AWBURST), .AWLOCK(g0_AWLOCK), .AWCACHE(g0_AWCACHE),
        .AWPROT(g0_AWPROT), .AWQOS(g0_AWQOS), .AWREGION(g0_AWREGION),
        .AWUSER(g0_AWUSER),
        .WVALID(g0_WVALID), .WREADY(g0_WREADY), .WDATA(g0_WDATA),
        .WSTRB(g0_WSTRB), .WLAST(g0_WLAST), .WID(g0_WID), .WUSER(g0_WUSER),
        .BVALID(g0_BVALID), .BREADY(g0_BREADY), .BRESP(g0_BRESP),
        .BID(g0_BID), .BUSER(g0_BUSER),
        .ARVALID(g0_ARVALID), .ARREADY(g0_ARREADY), .ARADDR(g0_ARADDR),
        .ARID(g0_ARID), .ARLEN(g0_ARLEN), .ARSIZE(g0_ARSIZE),
        .ARBURST(g0_ARBURST), .ARLOCK(g0_ARLOCK), .ARCACHE(g0_ARCACHE),
        .ARPROT(g0_ARPROT), .ARQOS(g0_ARQOS), .ARREGION(g0_ARREGION),
        .ARUSER(g0_ARUSER),
        .RVALID(g0_RVALID), .RREADY(g0_RREADY), .RDATA(g0_RDATA),
        .RLAST(g0_RLAST), .RID(g0_RID), .RRESP(g0_RRESP), .RUSER(g0_RUSER)
    );

    axi_mem_model #(
        .DATA_WIDTH(32), .ADDR_WIDTH(64), .ID_WIDTH(1),
        .USER_WIDTH(1), .MEM_SIZE(4096)  // 4KB for weight (576 字节足够)
    ) gmem1_mem (
        .ap_clk(ap_clk), .ap_rst_n(ap_rst_n),
        .AWVALID(g1_AWVALID), .AWREADY(g1_AWREADY), .AWADDR(g1_AWADDR),
        .AWID(g1_AWID), .AWLEN(g1_AWLEN), .AWSIZE(g1_AWSIZE),
        .AWBURST(g1_AWBURST), .AWLOCK(g1_AWLOCK), .AWCACHE(g1_AWCACHE),
        .AWPROT(g1_AWPROT), .AWQOS(g1_AWQOS), .AWREGION(g1_AWREGION),
        .AWUSER(g1_AWUSER),
        .WVALID(g1_WVALID), .WREADY(g1_WREADY), .WDATA(g1_WDATA),
        .WSTRB(g1_WSTRB), .WLAST(g1_WLAST), .WID(g1_WID), .WUSER(g1_WUSER),
        .BVALID(g1_BVALID), .BREADY(g1_BREADY), .BRESP(g1_BRESP),
        .BID(g1_BID), .BUSER(g1_BUSER),
        .ARVALID(g1_ARVALID), .ARREADY(g1_ARREADY), .ARADDR(g1_ARADDR),
        .ARID(g1_ARID), .ARLEN(g1_ARLEN), .ARSIZE(g1_ARSIZE),
        .ARBURST(g1_ARBURST), .ARLOCK(g1_ARLOCK), .ARCACHE(g1_ARCACHE),
        .ARPROT(g1_ARPROT), .ARQOS(g1_ARQOS), .ARREGION(g1_ARREGION),
        .ARUSER(g1_ARUSER),
        .RVALID(g1_RVALID), .RREADY(g1_RREADY), .RDATA(g1_RDATA),
        .RLAST(g1_RLAST), .RID(g1_RID), .RRESP(g1_RRESP), .RUSER(g1_RUSER)
    );

    axi_mem_model #(
        .DATA_WIDTH(32), .ADDR_WIDTH(64), .ID_WIDTH(1),
        .USER_WIDTH(1), .MEM_SIZE(256)  // 256B for bias
    ) gmem2_mem (
        .ap_clk(ap_clk), .ap_rst_n(ap_rst_n),
        .AWVALID(g2_AWVALID), .AWREADY(g2_AWREADY), .AWADDR(g2_AWADDR),
        .AWID(g2_AWID), .AWLEN(g2_AWLEN), .AWSIZE(g2_AWSIZE),
        .AWBURST(g2_AWBURST), .AWLOCK(g2_AWLOCK), .AWCACHE(g2_AWCACHE),
        .AWPROT(g2_AWPROT), .AWQOS(g2_AWQOS), .AWREGION(g2_AWREGION),
        .AWUSER(g2_AWUSER),
        .WVALID(g2_WVALID), .WREADY(g2_WREADY), .WDATA(g2_WDATA),
        .WSTRB(g2_WSTRB), .WLAST(g2_WLAST), .WID(g2_WID), .WUSER(g2_WUSER),
        .BVALID(g2_BVALID), .BREADY(g2_BREADY), .BRESP(g2_BRESP),
        .BID(g2_BID), .BUSER(g2_BUSER),
        .ARVALID(g2_ARVALID), .ARREADY(g2_ARREADY), .ARADDR(g2_ARADDR),
        .ARID(g2_ARID), .ARLEN(g2_ARLEN), .ARSIZE(g2_ARSIZE),
        .ARBURST(g2_ARBURST), .ARLOCK(g2_ARLOCK), .ARCACHE(g2_ARCACHE),
        .ARPROT(g2_ARPROT), .ARQOS(g2_ARQOS), .ARREGION(g2_ARREGION),
        .ARUSER(g2_ARUSER),
        .RVALID(g2_RVALID), .RREADY(g2_RREADY), .RDATA(g2_RDATA),
        .RLAST(g2_RLAST), .RID(g2_RID), .RRESP(g2_RRESP), .RUSER(g2_RUSER)
    );

    axi_mem_model #(
        .DATA_WIDTH(32), .ADDR_WIDTH(64), .ID_WIDTH(1),
        .USER_WIDTH(1), .MEM_SIZE(256)  // 256B for deq
    ) gmem3_mem (
        .ap_clk(ap_clk), .ap_rst_n(ap_rst_n),
        .AWVALID(g3_AWVALID), .AWREADY(g3_AWREADY), .AWADDR(g3_AWADDR),
        .AWID(g3_AWID), .AWLEN(g3_AWLEN), .AWSIZE(g3_AWSIZE),
        .AWBURST(g3_AWBURST), .AWLOCK(g3_AWLOCK), .AWCACHE(g3_AWCACHE),
        .AWPROT(g3_AWPROT), .AWQOS(g3_AWQOS), .AWREGION(g3_AWREGION),
        .AWUSER(g3_AWUSER),
        .WVALID(g3_WVALID), .WREADY(g3_WREADY), .WDATA(g3_WDATA),
        .WSTRB(g3_WSTRB), .WLAST(g3_WLAST), .WID(g3_WID), .WUSER(g3_WUSER),
        .BVALID(g3_BVALID), .BREADY(g3_BREADY), .BRESP(g3_BRESP),
        .BID(g3_BID), .BUSER(g3_BUSER),
        .ARVALID(g3_ARVALID), .ARREADY(g3_ARREADY), .ARADDR(g3_ARADDR),
        .ARID(g3_ARID), .ARLEN(g3_ARLEN), .ARSIZE(g3_ARSIZE),
        .ARBURST(g3_ARBURST), .ARLOCK(g3_ARLOCK), .ARCACHE(g3_ARCACHE),
        .ARPROT(g3_ARPROT), .ARQOS(g3_ARQOS), .ARREGION(g3_ARREGION),
        .ARUSER(g3_ARUSER),
        .RVALID(g3_RVALID), .RREADY(g3_RREADY), .RDATA(g3_RDATA),
        .RLAST(g3_RLAST), .RID(g3_RID), .RRESP(g3_RRESP), .RUSER(g3_RUSER)
    );

    axi_mem_model #(
        .DATA_WIDTH(32), .ADDR_WIDTH(64), .ID_WIDTH(1),
        .USER_WIDTH(1), .MEM_SIZE(1048576)  // 1MB for ofm (115200 字节)
    ) gmem4_mem (
        .ap_clk(ap_clk), .ap_rst_n(ap_rst_n),
        .AWVALID(g4_AWVALID), .AWREADY(g4_AWREADY), .AWADDR(g4_AWADDR),
        .AWID(g4_AWID), .AWLEN(g4_AWLEN), .AWSIZE(g4_AWSIZE),
        .AWBURST(g4_AWBURST), .AWLOCK(g4_AWLOCK), .AWCACHE(g4_AWCACHE),
        .AWPROT(g4_AWPROT), .AWQOS(g4_AWQOS), .AWREGION(g4_AWREGION),
        .AWUSER(g4_AWUSER),
        .WVALID(g4_WVALID), .WREADY(g4_WREADY), .WDATA(g4_WDATA),
        .WSTRB(g4_WSTRB), .WLAST(g4_WLAST), .WID(g4_WID), .WUSER(g4_WUSER),
        .BVALID(g4_BVALID), .BREADY(g4_BREADY), .BRESP(g4_BRESP),
        .BID(g4_BID), .BUSER(g4_BUSER),
        .ARVALID(g4_ARVALID), .ARREADY(g4_ARREADY), .ARADDR(g4_ARADDR),
        .ARID(g4_ARID), .ARLEN(g4_ARLEN), .ARSIZE(g4_ARSIZE),
        .ARBURST(g4_ARBURST), .ARLOCK(g4_ARLOCK), .ARCACHE(g4_ARCACHE),
        .ARPROT(g4_ARPROT), .ARQOS(g4_ARQOS), .ARREGION(g4_ARREGION),
        .ARUSER(g4_ARUSER),
        .RVALID(g4_RVALID), .RREADY(g4_RREADY), .RDATA(g4_RDATA),
        .RLAST(g4_RLAST), .RID(g4_RID), .RRESP(g4_RRESP), .RUSER(g4_RUSER)
    );

    // ============================================================
    // AXI-Lite Master 实例
    // ============================================================
    axi_lite_master ctrl_master (
        .ap_clk(ap_clk), .ap_rst_n(ap_rst_n),
        .AWVALID(c_AWVALID), .AWREADY(c_AWREADY), .AWADDR(c_AWADDR),
        .WVALID(c_WVALID), .WREADY(c_WREADY), .WDATA(c_WDATA), .WSTRB(c_WSTRB),
        .BVALID(c_BVALID), .BREADY(c_BREADY), .BRESP(c_BRESP),
        .ARVALID(c_ARVALID), .ARREADY(c_ARREADY), .ARADDR(c_ARADDR),
        .RVALID(c_RVALID), .RREADY(c_RREADY), .RDATA(c_RDATA), .RRESP(c_RRESP)
    );

    // ============================================================
    // 测试流程
    // ============================================================
    integer b, h, w, c, kh, kw, ic, oc;
    integer ifm_idx, wgt_idx, ofm_idx;
    reg [31:0] ctrl_data;
    integer errors;
    integer max_errors_print;
    integer total_checked;

    // 用 reg 数组存 int8/int32 数据
    reg signed [7:0] ifm_mem [0:IFM_SIZE-1];
    reg signed [7:0] wgt_mem [0:WGT_SIZE-1];
    reg signed [31:0] bias_mem [0:BIAS_SIZE-1];
    reg signed [31:0] deq_mem  [0:DEQ_SIZE-1];
    reg signed [7:0] ofm_mem [0:OFM_SIZE-1];
    reg signed [31:0] golden_mem [0:OFM_SIZE-1];

    // 提取 word 中第 i 个 byte (0=LSB)
    function signed [7:0] get_byte(input [31:0] word, input integer idx);
        begin
            case (idx)
                0: get_byte = word[7:0];
                1: get_byte = word[15:8];
                2: get_byte = word[23:16];
                3: get_byte = word[31:24];
                default: get_byte = 8'h00;
            endcase
        end
    endfunction

    // 写 1 个 int8 到 mem (按字节地址)
    task write_byte_to_gmem;
        input integer mem_idx;
        input integer byte_addr_in;
        input signed [7:0] val;
        reg [31:0] wdata;
        reg [31:0] cur;
        integer aligned_addr;
        integer byte_off;
        begin
            aligned_addr = (byte_addr_in / 4) * 4;
            byte_off = byte_addr_in % 4;
            case (mem_idx)
                0: cur = gmem0_mem.backdoor_read_word(aligned_addr);
                1: cur = gmem1_mem.backdoor_read_word(aligned_addr);
                2: cur = gmem2_mem.backdoor_read_word(aligned_addr);
                3: cur = gmem3_mem.backdoor_read_word(aligned_addr);
                4: cur = gmem4_mem.backdoor_read_word(aligned_addr);
                default: cur = 32'h0;
            endcase
            case (byte_off)
                0: wdata = {cur[31:8], val};
                1: wdata = {cur[31:16], val, cur[7:0]};
                2: wdata = {cur[31:24], val, cur[15:0]};
                3: wdata = {val, cur[23:0]};
                default: wdata = cur;
            endcase
            case (mem_idx)
                0: gmem0_mem.backdoor_write_word(aligned_addr, wdata);
                1: gmem1_mem.backdoor_write_word(aligned_addr, wdata);
                2: gmem2_mem.backdoor_write_word(aligned_addr, wdata);
                3: gmem3_mem.backdoor_write_word(aligned_addr, wdata);
                4: gmem4_mem.backdoor_write_word(aligned_addr, wdata);
            endcase
        end
    endtask

    // 读 1 个 int8 从 mem (按字节地址)
    function signed [7:0] read_byte_from_gmem;
        input integer mem_idx;
        input integer byte_addr_in;
        reg [31:0] cur;
        integer aligned_addr;
        integer byte_off;
        begin
            aligned_addr = (byte_addr_in / 4) * 4;
            byte_off = byte_addr_in % 4;
            case (mem_idx)
                0: cur = gmem0_mem.backdoor_read_word(aligned_addr);
                1: cur = gmem1_mem.backdoor_read_word(aligned_addr);
                2: cur = gmem2_mem.backdoor_read_word(aligned_addr);
                3: cur = gmem3_mem.backdoor_read_word(aligned_addr);
                4: cur = gmem4_mem.backdoor_read_word(aligned_addr);
                default: cur = 32'h0;
            endcase
            read_byte_from_gmem = get_byte(cur, byte_off);
        end
    endfunction

    // ============================================================
    // Golden 计算: int32 卷积 + bias + deq 乘法 + [0,127] 截断
    // ============================================================
    task compute_golden;
        integer ih, iw;
        reg signed [31:0] acc;
        reg signed [31:0] prod;
        begin
            for (b = 0; b < BATCH; b = b + 1) begin
                for (oc = 0; oc < OUT_C; oc = oc + 1) begin
                    for (h = 0; h < OUT_H; h = h + 1) begin
                        for (w = 0; w < OUT_W; w = w + 1) begin
                            acc = bias_mem[oc];
                            for (ic = 0; ic < IN_C; ic = ic + 1) begin
                                for (kh = 0; kh < KH; kh = kh + 1) begin
                                    for (kw = 0; kw < KW; kw = kw + 1) begin
                                        ih = h * STRIDE_H - PAD_H + kh * DIL_H;
                                        iw = w * STRIDE_W - PAD_W + kw * DIL_W;
                                        if (ih >= 0 && ih < IN_H && iw >= 0 && iw < IN_W) begin
                                            ifm_idx = b * IN_H * IN_W * IN_C + ih * IN_W * IN_C + iw * IN_C + ic;
                                            wgt_idx = oc * IN_C * KH * KW + ic * KH * KW + kh * KW + kw;
                                            acc = acc + ifm_mem[ifm_idx] * wgt_mem[wgt_idx];
                                        end
                                    end
                                end
                            end
                            // deq 乘法
                            prod = acc * deq_mem[oc];
                            // [0,127] 截断
                            if (prod > 127) prod = 127;
                            else if (prod < 0) prod = 0;
                            ofm_idx = b * OUT_H * OUT_W * OUT_C + h * OUT_W * OUT_C + w * OUT_C + oc;
                            golden_mem[ofm_idx] = prod;
                        end
                    end
                end
            end
        end
    endtask

    // ============================================================
    // 简化可视化: 仅打印前 4 行 × 8 列, 前 4 通道和后 2 通道
    // 90x160 较大, 全部打印不现实
    // ============================================================
    task visualize_results;
        integer oc_i, h_i, w_i, idx;
        reg signed [32:0] diff_val;
        begin
            for (oc_i = 0; oc_i < OUT_C; oc_i = oc_i + 1) begin
                if (oc_i > 3 && oc_i < OUT_C - 2) continue;  // 只打印 oc=0~3 和 oc=6~7
                $display("============================================================");
                $display("==== Channel %0d: ofm vs golden (first 4 rows x 8 cols) ====", oc_i);
                $display("     w=0    1    2    3    4    5    6    7");
                for (h_i = 0; h_i < 4; h_i = h_i + 1) begin
                    $write("h=%2d  ", h_i);
                    for (w_i = 0; w_i < 8; w_i = w_i + 1) begin
                        idx = h_i * OUT_W * OUT_C + w_i * OUT_C + oc_i;
                        $write("%4d ", ofm_mem[idx]);
                    end
                    $write(" | exp:");
                    for (w_i = 0; w_i < 8; w_i = w_i + 1) begin
                        idx = h_i * OUT_W * OUT_C + w_i * OUT_C + oc_i;
                        $write("%4d ", golden_mem[idx][7:0]);
                    end
                    $write(" | diff:");
                    for (w_i = 0; w_i < 8; w_i = w_i + 1) begin
                        idx = h_i * OUT_W * OUT_C + w_i * OUT_C + oc_i;
                        diff_val = ofm_mem[idx] - golden_mem[idx][7:0];
                        $write("%4d ", diff_val);
                    end
                    $write("\n");
                end
                $display("");
            end
        end
    endtask

    // ============================================================
    // 主流程
    // ============================================================
    integer timeout_cnt;
    reg done_flag;

    initial begin
        errors = 0;
        total_checked = 0;
        max_errors_print = 20;
        timeout_cnt = 0;
        done_flag = 0;

        $display("==== Testbench Start (int8 8ch 90x160x8 conv) ====");

        // ---- 复位 ----
        ap_rst_n = 0;
        #50;
        ap_rst_n = 1;
        #20;
        $display("[TB] Reset released at time %0t", $time);

        // ============================================================
        // 1. 初始化 ifm: 8 个通道, 使用 (idx%101)-50 模式
        //    范围: [-50, 50]
        //    用 backdoor_write_byte 直接写 (避免 read-modify-write, 加速 115200 次写入)
        // ============================================================
        $display("[TB] Loading ifm from hex file...");
        $readmemh("c:/Users/13780/Desktop/learn_python/gai/vivado_tb/ifm_8ch_90x160.hex", ifm_mem);
        // 批量写入 gmem0 (用 backdoor_write_byte)
        for (ifm_idx = 0; ifm_idx < IFM_SIZE; ifm_idx = ifm_idx + 1) begin
            gmem0_mem.backdoor_write_byte(ifm_idx, ifm_mem[ifm_idx]);
        end
        $display("[TB] ifm initialized: 115200 bytes (8 channels)");

        // ============================================================
        // 2. 初始化 weight: 8x8x3x3, +/-1 交替模式
        //    weight[oc][ic][kh][kw]: 如果 (oc+ic) % 2 == 0 则 +1, 否则 -1
        // ============================================================
        for (oc = 0; oc < OUT_C; oc = oc + 1) begin
            for (ic = 0; ic < IN_C; ic = ic + 1) begin
                for (kh = 0; kh < KH; kh = kh + 1) begin
                    for (kw = 0; kw < KW; kw = kw + 1) begin
                        wgt_idx = oc * IN_C * KH * KW + ic * KH * KW + kh * KW + kw;
                        // (oc+ic) % 2 == 0 则 +1, 否则 -1
                        if ((oc + ic) % 2 == 0) begin
                            wgt_mem[wgt_idx] = 8'sd1;
                        end else begin
                            wgt_mem[wgt_idx] = -8'sd1;
                        end
                        gmem1_mem.backdoor_write_byte(wgt_idx, wgt_mem[wgt_idx]);
                    end
                end
            end
        end
        $display("[TB] weight initialized: 576 bytes (8x8x3x3, +/-1 pattern)");

        // ============================================================
        // 3. bias = 0, deq = 1
        // ============================================================
        for (oc = 0; oc < OUT_C; oc = oc + 1) begin
            bias_mem[oc] = 32'sd0;
            deq_mem[oc]  = 32'sd1;
            gmem2_mem.backdoor_write_word(oc * 4, bias_mem[oc]);
            gmem3_mem.backdoor_write_word(oc * 4, deq_mem[oc]);
        end
        $display("[TB] bias=0, deq=1");

        // ============================================================
        // 4. 计算 golden
        // ============================================================
        $display("[TB] Loading golden from hex file...");
        $readmemh("c:/Users/13780/Desktop/learn_python/gai/vivado_tb/golden_8ch_90x160.hex", golden_mem);
        $display("[TB] golden loaded");

        // ============================================================
        // 5. 配置寄存器
        // ============================================================
        $display("[TB] Configuring registers...");

        ctrl_master.axi_write(ADDR_PARAMS + 0,  BATCH);     // batch=1
        ctrl_master.axi_write(ADDR_PARAMS + 4,  IN_H);      // in_height=90
        ctrl_master.axi_write(ADDR_PARAMS + 8,  IN_W);      // in_width=160
        ctrl_master.axi_write(ADDR_PARAMS + 12, OUT_H);     // out_height=90
        ctrl_master.axi_write(ADDR_PARAMS + 16, OUT_W);     // out_width=160
        ctrl_master.axi_write(ADDR_PARAMS + 20, IN_C);      // in_channel=8
        ctrl_master.axi_write(ADDR_PARAMS + 24, OUT_C);     // out_channel=8
        ctrl_master.axi_write(ADDR_PARAMS + 28, KH);        // kernel_h=3
        ctrl_master.axi_write(ADDR_PARAMS + 32, KW);        // kernel_w=3
        ctrl_master.axi_write(ADDR_PARAMS + 36, STRIDE_H);  // stride_h=1
        ctrl_master.axi_write(ADDR_PARAMS + 40, STRIDE_W);  // stride_w=1
        ctrl_master.axi_write(ADDR_PARAMS + 44, PAD_H);     // pad_h=1
        ctrl_master.axi_write(ADDR_PARAMS + 48, PAD_W);     // pad_w=1
        ctrl_master.axi_write(ADDR_PARAMS + 52, DIL_H);     // dilation_h=1
        ctrl_master.axi_write(ADDR_PARAMS + 56, DIL_W);     // dilation_w=1
        // Tiling 参数 (8 通道版本)
        // L1 oh 迭代 5 次 (90/18), L1 ow 迭代 5 次 (160/32)
        // L1 ic 迭代 2 次 (8/4), L1 oc 迭代 4 次 (8/2)
        ctrl_master.axi_write(ADDR_PARAMS + 60, 18);        // H_L1=18
        ctrl_master.axi_write(ADDR_PARAMS + 64, 32);        // W_L1=32
        ctrl_master.axi_write(ADDR_PARAMS + 68, 4);         // CI_L1=4
        ctrl_master.axi_write(ADDR_PARAMS + 72, 2);         // CO_L1=2
        ctrl_master.axi_write(ADDR_PARAMS + 76, 9);         // H_L0=9
        ctrl_master.axi_write(ADDR_PARAMS + 80, 16);        // W_L0=16
        ctrl_master.axi_write(ADDR_PARAMS + 84, 1);         // CI1_L0=1
        ctrl_master.axi_write(ADDR_PARAMS + 88, 2);         // CO_L0=2

        // 数据指针 (5 个 m_axi 端口基地址)
        ctrl_master.axi_write(ADDR_IFM,    32'h0000_0000);
        ctrl_master.axi_write(ADDR_WEIGHT, 32'h0000_0000);
        ctrl_master.axi_write(ADDR_BIAS,   32'h0000_0000);
        ctrl_master.axi_write(ADDR_DEQ,    32'h0000_0000);
        ctrl_master.axi_write(ADDR_OFM,    32'h0000_0000);

        ctrl_master.axi_write(ADDR_ZERO_PT,   32'h0000_0000);
        ctrl_master.axi_write(ADDR_QT_EN,     32'h0000_0000);
        ctrl_master.axi_write(ADDR_QT_SCALE,  32'h0000_0000);
        ctrl_master.axi_write(ADDR_QT_OFFSET, 32'h0000_0000);

        $display("[TB] Registers configured");

        // ============================================================
        // 6. 启动 IP: ap_start = 1
        // ============================================================
        $display("[TB] Starting IP...");
        ctrl_master.axi_write(ADDR_AP_CTRL, 32'h0000_0001);

        // 读回 ap_ctrl 确认 ap_start 被置位
        ctrl_master.axi_read(ADDR_AP_CTRL, ctrl_data);
        $display("[TB] After start: ap_ctrl = 0x%08x (bit0=ap_start, bit1=ap_done, bit2=ap_idle, bit3=ap_ready)",
                 ctrl_data);

        // ============================================================
        // 7. 等待 IP 完成 (ap_done)
        // 500ms 仿真时间 (500000 次轮询 * 100 拍 * 10ns = 500ms)
        // 115200 个 ofm 元素, 8 通道, 预计仿真时间 ~400ms
        // ============================================================
        timeout_cnt = 0;
        done_flag = 0;
        while (!done_flag && timeout_cnt < 500000) begin
            repeat(100) @(posedge ap_clk);
            ctrl_master.axi_read(ADDR_AP_CTRL, ctrl_data);
            if (ctrl_data[1] === 1'b1) done_flag = 1;
            // 前 5000 次每 1000 次打印一次 (1ms), 之后每 20000 次打印一次 (20ms)
            if (timeout_cnt > 0 && ((timeout_cnt < 5000 && timeout_cnt % 1000 == 0) || timeout_cnt % 20000 == 0)) begin
                $display("[TB] poll %0d (time %0t): ap_ctrl=0x%08x, g0 AR=%0d g1 AR=%0d g4 W=%0d",
                         timeout_cnt, $time, ctrl_data,
                         gmem0_mem.get_ar_txn_count(), gmem1_mem.get_ar_txn_count(),
                         gmem4_mem.get_w_beat_count());
            end
            timeout_cnt = timeout_cnt + 1;
        end

        // 一次性打印所有调试信息
        $display("[TB] After %0d polls (time %0t):", timeout_cnt, $time);
        $display("[TB]   ap_ctrl = 0x%08x (ap_start=%b ap_done=%b ap_idle=%b ap_ready=%b)",
                 ctrl_data, ctrl_data[0], ctrl_data[1], ctrl_data[2], ctrl_data[3]);
        $display("[TB]   gmem0(ifm):  AR txn=%0d, AW txn=%0d, W beats=%0d",
                 gmem0_mem.get_ar_txn_count(), gmem0_mem.get_aw_txn_count(), gmem0_mem.get_w_beat_count());
        $display("[TB]   gmem1(wgt):  AR txn=%0d, AW txn=%0d, W beats=%0d",
                 gmem1_mem.get_ar_txn_count(), gmem1_mem.get_aw_txn_count(), gmem1_mem.get_w_beat_count());
        $display("[TB]   gmem2(bias): AR txn=%0d, AW txn=%0d, W beats=%0d",
                 gmem2_mem.get_ar_txn_count(), gmem2_mem.get_aw_txn_count(), gmem2_mem.get_w_beat_count());
        $display("[TB]   gmem3(deq):  AR txn=%0d, AW txn=%0d, W beats=%0d",
                 gmem3_mem.get_ar_txn_count(), gmem3_mem.get_aw_txn_count(), gmem3_mem.get_w_beat_count());
        $display("[TB]   gmem4(ofm):  AR txn=%0d, AW txn=%0d, W beats=%0d",
                 gmem4_mem.get_ar_txn_count(), gmem4_mem.get_aw_txn_count(), gmem4_mem.get_w_beat_count());

        if (!done_flag) begin
            $display("[TB] TIMEOUT waiting for ap_done after %0d iterations, last ap_ctrl = 0x%08x",
                     timeout_cnt, ctrl_data);
            $display("[TB] Final ap_ctrl bits: ap_start=%b ap_done=%b ap_idle=%b ap_ready=%b",
                     ctrl_data[0], ctrl_data[1], ctrl_data[2], ctrl_data[3]);
            $display("==== TEST FAIL (timeout) ====");

            // 即使超时也读出 ofm 看看部分写入情况
            $display("[TB] Reading partial ofm despite timeout...");
            for (ofm_idx = 0; ofm_idx < OFM_SIZE; ofm_idx = ofm_idx + 1) begin
                ofm_mem[ofm_idx] = gmem4_mem.backdoor_read_byte(ofm_idx);
            end
            visualize_results();
            $finish;
        end
        $display("[TB] IP done after %0d polls (~%0t)", timeout_cnt, $time);

        // ============================================================
        // 8. 读取 ofm 并比较
        // ============================================================
        $display("[TB] Comparing results...");
        for (ofm_idx = 0; ofm_idx < OFM_SIZE; ofm_idx = ofm_idx + 1) begin
            ofm_mem[ofm_idx] = gmem4_mem.backdoor_read_byte(ofm_idx);
            total_checked = total_checked + 1;
            if (ofm_mem[ofm_idx] !== golden_mem[ofm_idx][7:0]) begin
                errors = errors + 1;
                if (errors <= max_errors_print) begin
                    b  = ofm_idx / (OUT_H * OUT_W * OUT_C);
                    h  = (ofm_idx % (OUT_H * OUT_W * OUT_C)) / (OUT_W * OUT_C);
                    w  = (ofm_idx % (OUT_W * OUT_C)) / OUT_C;
                    oc = ofm_idx % OUT_C;
                    $display("[ERR] ofm[%0d][%0d][%0d][%0d]: got=%0d, exp=%0d",
                             b, h, w, oc, ofm_mem[ofm_idx], golden_mem[ofm_idx][7:0]);
                end
            end
        end

        // ============================================================
        // 9. 简化可视化: 只打印前 4 行 × 8 列的对照
        // ============================================================
        visualize_results();

        $display("============================================================");
        $display("Total checked: %0d", total_checked);
        $display("Errors:        %0d", errors);
        if (errors == 0) begin
            $display("==== TEST PASS ====");
        end else begin
            $display("==== TEST FAIL ====");
        end
        $display("============================================================");

        $finish;
    end

    // 超时保护 (1 秒仿真时间, 500ms 轮询 + 500ms 余量)
    // 115200 个 ofm 元素, 预计 ~100ms, 1s 足够
    initial begin
        #1_000_000_000;
        $display("[TB] HARD TIMEOUT at 1s, forcing finish");
        $finish;
    end

endmodule
