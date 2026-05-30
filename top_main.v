`timescale 1ns / 1ps
//==============================================================================
// 모듈명 : top_main
// 기  능 : OV7670 카메라 + VGA 출력 SoC의 최상위 모듈.
//
// 시스템 구성:
//   clk_wiz_0      : 24MHz (카메라 MCLK), 25MHz (VGA 픽셀 클럭) 생성
//   ov7670_init    : SCCB로 카메라 레지스터 초기화 (CPU_en으로 시작)
//   ov7670_capture : PCLK 동기로 픽셀 수신 → BRAM Write 포트
//   blk_mem_gen_0  : 320×240 × 12bit 듀얼포트 프레임 버퍼
//                    (Port A: PCLK 도메인 쓰기 / Port B: 25MHz 도메인 읽기)
//   vga_controller : BRAM 읽기 → 640×480@60Hz VGA 출력
//
// 클럭 도메인:
//   PCLK (카메라)  → BRAM Port A 쓰기
//   clk_25M        → BRAM Port B 읽기 + VGA 신호 생성
//   clk_24M        → SCCB 초기화 + 카메라 MCLK 공급
//
// 리셋 전략:
//   ov7670_capture의 리셋은 locked & init_done이 모두 만족된 이후 해제.
//   초기화 전 캡처 모듈이 활성화되면 BRAM에 쓰레기 데이터가 기록되므로
//   init_done을 추가 조건으로 사용한다.
//
// 디버그 LED:
//   led_clk1 = init_done  : 카메라 초기화 완료 확인
//   led_clk2 = Camera_Vs  : 카메라 VSYNC 동작 확인
//   led_clk3 = VGA Vsync  : VGA 출력 동작 확인
//   led_clk4 = locked     : PLL 안정화 확인
//==============================================================================

module top_main(
    input        wclk,
    input        btnC,           // 리셋 버튼 (Active High)

    input        CPU_en,         // 카메라 초기화 시작 신호 (SW 입력)
    input        PCLK_0,
    input        Camera_Vs_0,
    input        Camera_Hs_0,
    input  [7:0] image_data_0,
    output       MCLK,           // 카메라 마스터 클럭 (24MHz)
    output       SIO_C,          // SCCB 클럭
    inout        SIO_D,          // SCCB 데이터

    output       ov7670_pwdn,
    output       ov7670_reset,

    output       Hsync,
    output       Vsync,
    output [3:0] vgaRed_0, vgaGreen_0, vgaBlue_0,

    output       led_clk1, led_clk2, led_clk3, led_clk4
);

    assign ov7670_pwdn  = 0;
    // 하드웨어 리셋핀 비활성 고정. 소프트웨어 리셋(COM7[7])으로 대체.
    assign ov7670_reset = 1;
    wire rstn = !btnC;

    wire clk_24M, clk_25M, locked;
    wire [16:0] write_addr, read_addr;
    wire [11:0] write_data, read_data;
    wire write_en;
    wire init_done;

    clk_wiz_0 cw0 (
        .clk_in1(wclk),
        .reset(btnC),
        .clk_out1(clk_24M),
        .clk_out2(clk_25M),
        .locked(locked)
    );
    assign MCLK = clk_24M;

    ov7670_init init0 (
        .clk(clk_24M),
        .rstn(rstn && locked),
        .CPU_en(CPU_en),
        .scl(SIO_C),
        .sda(SIO_D),
        .done(init_done)
    );

    // PLL 안정화 + 카메라 초기화 완료 이후에 캡처 모듈 리셋 해제
    ov7670_capture cap0 (
        .pclk(PCLK_0),
        .rstn(rstn && locked && init_done),
        .vsync(Camera_Vs_0),
        .href(Camera_Hs_0),
        .d(image_data_0),
        .addr(write_addr),
        .dout(write_data),
        .we(write_en)
    );

    // 듀얼포트 BRAM: Port A(PCLK 도메인) 쓰기 / Port B(25MHz 도메인) 읽기
    blk_mem_gen_0 bram0 (
        .clka(PCLK_0),
        .ena(1'b1),
        .wea(write_en),
        .addra(write_addr),
        .dina(write_data),
        .clkb(clk_25M),
        .enb(1'b1),
        .addrb(read_addr),
        .doutb(read_data)
    );

    vga_controller vga0 (
        .clk_25M(clk_25M),
        .rstn(rstn && locked),
        .hsync(Hsync),
        .vsync(Vsync),
        .r(vgaRed_0), .g(vgaGreen_0), .b(vgaBlue_0),
        .rd_addr(read_addr),
        .pixel_data(read_data)
    );

    assign led_clk1 = init_done;
    assign led_clk2 = Camera_Vs_0;
    assign led_clk3 = Vsync;
    assign led_clk4 = locked;

endmodule
