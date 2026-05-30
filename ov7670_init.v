`timescale 1ns / 1ps
//==============================================================================
// 모듈명 : ov7670_init
// 기  능 : SCCB(I2C 호환) 프로토콜로 OV7670 카메라 레지스터를 초기화한다.
//
// 동작 원리:
//   시스템 클럭(24MHz)을 601분주하여 약 40kHz의 SCCB 클럭을 생성한다.
//   CPU_en이 High가 되면 14개의 레지스터를 순차적으로 기록하고,
//   모두 완료되면 done=1을 출력한다.
//
// SCCB 프레임 구조: [START] → {slave_addr, ACK} → {reg_addr, ACK} → {data, ACK} → [STOP]
//   shift_reg[26:0] = {addr[7:0], 1'b1, reg[7:0], 1'b1, data[7:0], 1'b1}
//   (ACK 비트는 don't-care로 1 고정, OV7670이 별도 회신 없음)
//
// 상태머신 (state):
//   0: IDLE / 다음 레지스터 준비
//   1: START 조건 생성 (SDA Low)
//   2: SCL Low → SDA 세팅
//   3: SCL High → 데이터 래치
//   4: STOP 전 SCL Low
//   5: STOP 전 SCL High
//   6: STOP 조건 생성 (SDA High)
//   7: 레지스터 간 대기 (~125 µs)
//
// 레지스터 구성: RGB565 풀레인지, QVGA(320×240), AWB/AEC 자동 보정 활성화
//==============================================================================

module ov7670_init(
    input      clk,        // 시스템 클럭 (24MHz)
    input      rstn,
    input      CPU_en,     // 초기화 시작 신호 (CPU/SW 제어)
    output reg scl,        // SCCB 클럭
    inout      sda,        // SCCB 데이터 (오픈드레인)
    output reg cam_reset,  // 카메라 하드웨어 리셋 (비활성 유지)
    output reg done        // 전체 레지스터 기록 완료 플래그
);

    // --- SCCB 클럭 생성 (24MHz / 601 ≈ 40kHz) ---
    reg [11:0] clk_cnt;
    reg sccb_clk;
    always @(posedge clk) begin
        if (clk_cnt == 300) begin clk_cnt <= 0; sccb_clk <= ~sccb_clk; end
        else clk_cnt <= clk_cnt + 1;
    end

    reg [7:0]  state;
    reg [5:0]  reg_idx;     // 현재 기록 중인 레지스터 인덱스 (0~13)
    reg [26:0] shift_reg;   // 27비트 직렬 송신 레지스터
    reg [4:0]  bit_cnt;
    reg [23:0] wait_cnt;

    // --- 레지스터 설정 테이블 ---
    // 형식: {SCCB_슬레이브주소[7:0], 레지스터주소[7:0], 설정값[7:0]}
    wire [23:0] current_config;
    assign current_config =
        (reg_idx == 0)  ? 24'h42_12_80 : // COM7:  소프트웨어 리셋
        (reg_idx == 1)  ? 24'h42_12_04 : // COM7:  RGB 모드, QVGA 해상도
        (reg_idx == 2)  ? 24'h42_11_01 : // CLKRC: PCLK 프리스케일러 = 1
        (reg_idx == 3)  ? 24'h42_40_D0 : // COM15: RGB565 풀레인지 (0x00~0xFF)
        (reg_idx == 4)  ? 24'h42_13_E7 : // COM8:  자동 화이트밸런스/노출/게인 활성화
        (reg_idx == 5)  ? 24'h42_01_40 : // BLUE:  청색 채널 게인
        (reg_idx == 6)  ? 24'h42_02_60 : // RED:   적색 채널 게인
        (reg_idx == 7)  ? 24'h42_0C_00 : // COM3:  기본값
        (reg_idx == 8)  ? 24'h42_3E_00 : // COM14: 기본값
        (reg_idx == 9)  ? 24'h42_3D_C0 : // COM13: 감마/색상 행렬 활성화
        (reg_idx == 10) ? 24'h42_B0_84 : // Reserved: 색감 보정
        (reg_idx == 11) ? 24'h42_17_11 : // HSTART: 수평 프레임 시작 오프셋
        (reg_idx == 12) ? 24'h42_18_61 : // HSTOP:  수평 프레임 끝 오프셋
        (reg_idx == 13) ? 24'h42_32_A4 : // HREF:   HREF 에지 오프셋
        24'h42_12_04;

    // SDA 오픈드레인 구동: sda_out=0이면 Low, 1이면 High-Z (풀업에 의해 High)
    reg sda_out;
    assign sda = (sda_out) ? 1'bz : 1'b0;

    // --- SCCB 상태머신 ---
    always @(posedge sccb_clk or negedge rstn) begin
        if (!rstn) begin
            state <= 0; reg_idx <= 0; bit_cnt <= 0; wait_cnt <= 0;
            sda_out <= 1; scl <= 1; done <= 0; cam_reset <= 1;
        end else begin
            case(state)
                0: begin
                    if(!CPU_en)begin
                        done    <= 0;
                        reg_idx <= 0;
                    end
                    else if (reg_idx < 14) begin
                        // 27비트 송신 레지스터 구성 (각 바이트 뒤 ACK=1 삽입)
                        shift_reg <= {current_config[23:16], 1'b1,
                                      current_config[15:8],  1'b1,
                                      current_config[7:0],   1'b1};
                        state <= 1; sda_out <= 1; scl <= 1;
                    end else begin
                        done <= 1;
                    end
                end
                1: begin sda_out <= 0; bit_cnt <= 26; state <= 2; end  // START 조건
                2: begin scl <= 0; sda_out <= shift_reg[bit_cnt]; state <= 3; end
                3: begin scl <= 1;
                    if (bit_cnt == 0) state <= 4;
                    else begin bit_cnt <= bit_cnt - 1; state <= 2; end
                end
                4: begin scl <= 0; sda_out <= 0; state <= 5; end
                5: begin scl <= 1; state <= 6; end
                6: begin sda_out <= 1; state <= 7; wait_cnt <= 0; end  // STOP 조건
                7: begin
                    // 레지스터 간 대기 (5000 SCCB클럭 ≈ 125µs)
                    if (wait_cnt < 5000) wait_cnt <= wait_cnt + 1;
                    else begin reg_idx <= reg_idx + 1; state <= 0; end
                end
            endcase
        end
    end

endmodule
