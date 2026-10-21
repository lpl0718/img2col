// ============================================================
// AXI BFM (Bus Functional Models) for op_convolution_full testing
// 包含:
//   1. axi_mem_model  — AXI4 Slave 存储模型 (模拟 DDR, 支持突发读写)
//   2. axi_lite_master — AXI-Lite Master 驱动 (task 接口配置寄存器)
// ============================================================

`timescale 1ns / 1ps

// ============================================================
// AXI4 Slave 存储模型
// 每个实例有独立的 backing memory, 模拟一段 DDR 地址空间
// 支持: INCR 突发, WSTRB 字节写掩码, backdoor 读写 API
// ============================================================
module axi_mem_model #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 64,
    parameter ID_WIDTH   = 1,
    parameter USER_WIDTH = 1,
    parameter MEM_SIZE   = 65536  // backing memory 字节数
)(
    input  wire                          ap_clk,
    input  wire                          ap_rst_n,
    // AW
    input  wire                          AWVALID,
    output wire                          AWREADY,
    input  wire [ADDR_WIDTH-1:0]         AWADDR,
    input  wire [ID_WIDTH-1:0]           AWID,
    input  wire [7:0]                    AWLEN,
    input  wire [2:0]                    AWSIZE,
    input  wire [1:0]                    AWBURST,
    input  wire [1:0]                    AWLOCK,
    input  wire [3:0]                    AWCACHE,
    input  wire [2:0]                    AWPROT,
    input  wire [3:0]                    AWQOS,
    input  wire [3:0]                    AWREGION,
    input  wire [USER_WIDTH-1:0]         AWUSER,
    // W
    input  wire                          WVALID,
    output wire                          WREADY,
    input  wire [DATA_WIDTH-1:0]         WDATA,
    input  wire [DATA_WIDTH/8-1:0]       WSTRB,
    input  wire                          WLAST,
    input  wire [ID_WIDTH-1:0]           WID,
    input  wire [USER_WIDTH-1:0]         WUSER,
    // B
    output wire                          BVALID,
    input  wire                          BREADY,
    output wire [1:0]                    BRESP,
    output wire [ID_WIDTH-1:0]           BID,
    output wire [USER_WIDTH-1:0]         BUSER,
    // AR
    input  wire                          ARVALID,
    output wire                          ARREADY,
    input  wire [ADDR_WIDTH-1:0]         ARADDR,
    input  wire [ID_WIDTH-1:0]           ARID,
    input  wire [7:0]                    ARLEN,
    input  wire [2:0]                    ARSIZE,
    input  wire [1:0]                    ARBURST,
    input  wire [1:0]                    ARLOCK,
    input  wire [3:0]                    ARCACHE,
    input  wire [2:0]                    ARPROT,
    input  wire [3:0]                    ARQOS,
    input  wire [3:0]                    ARREGION,
    input  wire [USER_WIDTH-1:0]         ARUSER,
    // R
    output wire                          RVALID,
    input  wire                          RREADY,
    output wire [DATA_WIDTH-1:0]         RDATA,
    output wire                          RLAST,
    output wire [ID_WIDTH-1:0]           RID,
    output wire [1:0]                    RRESP,
    output wire [USER_WIDTH-1:0]         RUSER
);
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // backing memory (byte-addressable)
    reg [7:0] mem [0:MEM_SIZE-1];

    // ============== Write 通道 ==============
    reg [ADDR_WIDTH-1:0] cur_aw_addr;
    reg [7:0]  cur_aw_len;
    reg [ID_WIDTH-1:0] cur_aw_id;
    reg [7:0]  w_beat_cnt;
    reg [15:0] b_outstanding;  // 待处理的 B 响应计数 (支持多 outstanding, 修复单 beat 写丢失 B 响应的 bug)
    reg [ID_WIDTH-1:0] b_id_r;

    // AW/W 始终就绪 (无背压, 简化设计)
    assign AWREADY = 1'b1;
    assign WREADY  = 1'b1;
    assign BVALID  = (b_outstanding > 0);  // 组合输出: 有待处理 B 响应即拉高
    assign BRESP   = 2'b00;
    assign BID     = b_id_r;
    assign BUSER   = {USER_WIDTH{1'b0}};

    integer i;
    reg [ADDR_WIDTH-1:0] wr_addr;   // 当前 W beat 对应的字节地址
    reg aw_pending;                  // 已收到 AW 但 W 还没来, 或 AW/W 同拍需用 AWADDR

    // 事务计数器 (供 TB backdoor 读取, 判断 IP 是否在干活)
    integer ar_txn_cnt;   // 读事务计数
    integer aw_txn_cnt;   // 写事务计数
    integer w_beat_cnt_total;  // W beat 总数

    always @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            w_beat_cnt <= 0;
            b_outstanding <= 0;
            cur_aw_addr <= 0;
            cur_aw_len  <= 0;
            cur_aw_id   <= 0;
            aw_pending  <= 0;
            ar_txn_cnt <= 0;
            aw_txn_cnt <= 0;
            w_beat_cnt_total <= 0;
        end else begin
            // 接收 AW
            if (AWVALID && AWREADY) begin
                cur_aw_addr <= AWADDR;
                cur_aw_len  <= AWLEN;
                cur_aw_id   <= AWID;
                aw_pending  <= 1;
                aw_txn_cnt <= aw_txn_cnt + 1;
            end
            // 接收 W
            if (WVALID && WREADY) begin
                w_beat_cnt_total <= w_beat_cnt_total + 1;
                // 计算本 beat 用的基地址:
                //   若本拍刚收到 AW (aw_pending 由本拍 AW 置位, 但 NBA 下拍才生效),
                //   且 w_beat_cnt==0 (第一 beat), 则用 AWADDR; 否则用 cur_aw_addr
                if (AWVALID && AWREADY && (w_beat_cnt == 0)) begin
                    wr_addr = AWADDR;  // 阻塞赋值, 立即用于本 beat
                end else begin
                    wr_addr = cur_aw_addr;
                end
                for (i = 0; i < STRB_WIDTH; i = i + 1) begin
                    if (WSTRB[i]) begin
                        mem[(wr_addr[31:0] + w_beat_cnt * STRB_WIDTH + i) % MEM_SIZE] <= WDATA[i*8 +: 8];
                    end
                end
                if (WLAST) begin
                    w_beat_cnt <= 0;
                    b_id_r     <= cur_aw_id;
                    aw_pending <= 0;
                end else begin
                    w_beat_cnt <= w_beat_cnt + 1;
                end
            end
            // b_outstanding 更新 (修复 WLAST 与 BREADY 同拍竞争 bug):
            //   WLAST + BREADY 同拍: 净变化 0 (不能让 -1 覆盖 +1)
            //   只 WLAST: +1
            //   只 BREADY: -1
            //   都没有: 保持
            case ({(WVALID && WREADY && WLAST), (BVALID && BREADY)})
                2'b10: b_outstanding <= b_outstanding + 1;
                2'b01: b_outstanding <= b_outstanding - 1;
                default: b_outstanding <= b_outstanding;  // 2'b00 或 2'b11
            endcase
        end
    end

    // ============== Read 通道 ==============
    reg [ADDR_WIDTH-1:0] cur_ar_addr;
    reg [7:0]  cur_ar_len;
    reg [ID_WIDTH-1:0] cur_ar_id;
    reg [7:0]  r_beat_cnt;
    reg        r_active;

    assign ARREADY = !r_active;
    assign RVALID  = r_active;
    assign RLAST   = r_active && (r_beat_cnt == cur_ar_len);
    assign RID     = cur_ar_id;
    assign RRESP   = 2'b00;
    assign RUSER   = {USER_WIDTH{1'b0}};

    // RDATA 组合读 (小 memory 下 xsim 可正确处理)
    assign RDATA = {
        mem[(cur_ar_addr[31:0] + r_beat_cnt*4 + 3) % MEM_SIZE],
        mem[(cur_ar_addr[31:0] + r_beat_cnt*4 + 2) % MEM_SIZE],
        mem[(cur_ar_addr[31:0] + r_beat_cnt*4 + 1) % MEM_SIZE],
        mem[(cur_ar_addr[31:0] + r_beat_cnt*4 + 0) % MEM_SIZE]
    };

    always @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            r_active    <= 0;
            r_beat_cnt  <= 0;
            cur_ar_addr <= 0;
            cur_ar_len  <= 0;
            cur_ar_id   <= 0;
            ar_txn_cnt  <= 0;
        end else begin
            if (!r_active) begin
                if (ARVALID && ARREADY) begin
                    cur_ar_addr <= ARADDR;
                    cur_ar_len  <= ARLEN;
                    cur_ar_id   <= ARID;
                    r_active    <= 1;
                    r_beat_cnt  <= 0;
                    ar_txn_cnt  <= ar_txn_cnt + 1;
                end
            end else begin
                if (RREADY) begin
                    if (r_beat_cnt == cur_ar_len) begin
                        r_active   <= 0;
                    end else begin
                        r_beat_cnt <= r_beat_cnt + 1;
                    end
                end
            end
        end
    end

    // ============== Backdoor API (供 TB 直接访问) ==============
    task backdoor_write_word(input [31:0] addr, input [31:0] data);
        begin
            mem[addr % MEM_SIZE]     = data[7:0];
            mem[(addr+1) % MEM_SIZE] = data[15:8];
            mem[(addr+2) % MEM_SIZE] = data[23:16];
            mem[(addr+3) % MEM_SIZE] = data[31:24];
        end
    endtask

    // 直接写单字节 (避免 read-modify-write, 加速大数组初始化)
    task backdoor_write_byte(input [31:0] addr, input [7:0] data);
        begin
            mem[addr % MEM_SIZE] = data;
        end
    endtask

    function [31:0] backdoor_read_word(input [31:0] addr);
        begin
            backdoor_read_word = {mem[(addr+3) % MEM_SIZE],
                                  mem[(addr+2) % MEM_SIZE],
                                  mem[(addr+1) % MEM_SIZE],
                                  mem[addr % MEM_SIZE]};
        end
    endfunction

    // 直接读单字节 (加速大数组读取)
    function [7:0] backdoor_read_byte(input [31:0] addr);
        begin
            backdoor_read_byte = mem[addr % MEM_SIZE];
        end
    endfunction

    // 事务计数器 backdoor 读取 (供 TB 判断 IP 是否在干活)
    function [31:0] get_ar_txn_count();
        begin
            get_ar_txn_count = ar_txn_cnt;
        end
    endfunction

    function [31:0] get_aw_txn_count();
        begin
            get_aw_txn_count = aw_txn_cnt;
        end
    endfunction

    function [31:0] get_w_beat_count();
        begin
            get_w_beat_count = w_beat_cnt_total;
        end
    endfunction

    // 初始化整个 memory 为 0
    initial begin
        for (integer j = 0; j < MEM_SIZE; j = j + 1)
            mem[j] = 8'h00;
    end
endmodule


// ============================================================
// AXI-Lite Master 驱动
// 提供 task: axi_write(addr, data), axi_read(addr, data)
// 注意: BVALID/BREADY/RVALID/RREADY 方向与 slave 相反
//   BVALID — slave 输出, master 输入
//   BREADY — master 输出, slave 输入
//   RVALID — slave 输出, master 输入
//   RREADY — master 输出, slave 输入
// ============================================================
module axi_lite_master #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  wire                          ap_clk,
    input  wire                          ap_rst_n,
    // AW (master -> slave)
    output reg                           AWVALID,
    input  wire                          AWREADY,
    output reg  [ADDR_WIDTH-1:0]         AWADDR,
    // W (master -> slave)
    output reg                           WVALID,
    input  wire                          WREADY,
    output reg  [DATA_WIDTH-1:0]         WDATA,
    output reg  [DATA_WIDTH/8-1:0]       WSTRB,
    // B (slave -> master)
    input  wire                          BVALID,
    output reg                           BREADY,
    input  wire [1:0]                    BRESP,
    // AR (master -> slave)
    output reg                           ARVALID,
    input  wire                          ARREADY,
    output reg  [ADDR_WIDTH-1:0]         ARADDR,
    // R (slave -> master)
    input  wire                          RVALID,
    output reg                           RREADY,
    input  wire [DATA_WIDTH-1:0]         RDATA,
    input  wire [1:0]                    RRESP
);
    // 复位时信号清零 (用 initial 初始化, 避免和 task 的 NBA 冲突)
    initial begin
        AWVALID = 1'b0;
        WVALID  = 1'b0;
        BREADY  = 1'b0;
        ARVALID = 1'b0;
        RREADY  = 1'b0;
        WSTRB   = 1'b0;
        AWADDR  = 0;
        ARADDR  = 0;
        WDATA   = 0;
    end

    // ============== Task API ==============
    // 关键: 所有信号驱动用 NBA (<=), 这样 slave 在 posedge 采样时
    // 看到的是上一拍的稳定值, 不会有 Verilog 调度竞争
    task axi_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        integer timeout_cnt;
        begin
            @(posedge ap_clk);
            // 用 NBA 驱动, 下一拍 slave 才采样
            AWADDR  <= addr;
            AWVALID <= 1'b1;
            WDATA   <= data;
            WSTRB   <= {(DATA_WIDTH/8){1'b1}};
            WVALID  <= 1'b1;

            // 等 AWREADY (slave 在 posedge 采样 AWVALID, 状态机用 NBA 转换)
            timeout_cnt = 0;
            @(posedge ap_clk);  // 第一拍: slave 采样 AWVALID=1
            while (!(AWREADY === 1'b1)) begin
                @(posedge ap_clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 1000) begin
                    $display("[AXI_LITE_WR] TIMEOUT waiting AWREADY, addr=0x%0x", addr);
                    AWVALID <= 1'b0;
                    WVALID  <= 1'b0;
                    return;
                end
            end
            // 此 posedge AWREADY=1, aw_hs=1, slave 将 wstate<=WRDATA (NBA)
            // 用 NBA 清 AWVALID, slave 此拍已采样到 AWVALID=1
            AWVALID <= 1'b0;

            // 等 WREADY (wstate 变为 WRDATA 后 WREADY=1)
            timeout_cnt = 0;
            while (!(WREADY === 1'b1)) begin
                @(posedge ap_clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 1000) begin
                    $display("[AXI_LITE_WR] TIMEOUT waiting WREADY, addr=0x%0x", addr);
                    WVALID <= 1'b0;
                    return;
                end
            end
            // w_hs=1, slave 将 wstate<=WRRESP
            WVALID <= 1'b0;
            WSTRB  <= 1'b0;
            BREADY <= 1'b1;

            // 等 BVALID (wstate 变为 WRRESP 后 BVALID=1)
            timeout_cnt = 0;
            while (!(BVALID === 1'b1)) begin
                @(posedge ap_clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 1000) begin
                    $display("[AXI_LITE_WR] TIMEOUT waiting BVALID, addr=0x%0x", addr);
                    BREADY <= 1'b0;
                    return;
                end
            end
            // b_hs=1, slave 将 wstate<=WRIDLE
            @(posedge ap_clk);
            BREADY <= 1'b0;
        end
    endtask

    // 读操作: AR 通道握手 -> R 通道数据
    task axi_read(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] data);
        integer timeout_cnt;
        begin
            @(posedge ap_clk);
            ARADDR  <= addr;
            ARVALID <= 1'b1;

            timeout_cnt = 0;
            @(posedge ap_clk);
            while (!(ARREADY === 1'b1)) begin
                @(posedge ap_clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 1000) begin
                    $display("[AXI_LITE_RD] TIMEOUT waiting ARREADY, addr=0x%0x", addr);
                    ARVALID <= 1'b0;
                    data = 32'hxxxx_xxxx;
                    return;
                end
            end
            ARVALID <= 1'b0;
            RREADY  <= 1'b1;

            timeout_cnt = 0;
            while (!(RVALID === 1'b1)) begin
                @(posedge ap_clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 1000) begin
                    $display("[AXI_LITE_RD] TIMEOUT waiting RVALID, addr=0x%0x", addr);
                    RREADY <= 1'b0;
                    data = 32'hxxxx_xxxx;
                    return;
                end
            end
            data = RDATA;
            @(posedge ap_clk);
            RREADY <= 1'b0;
        end
    endtask
endmodule
