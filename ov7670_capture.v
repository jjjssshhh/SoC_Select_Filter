`timescale 1ns / 1ps
//==============================================================================
// 모듈명 : ov7670_capture
// 기  능 : OV7670 카메라에서 RGB565 픽셀 데이터를 수신하여 프레임 버퍼(BRAM)에
//          저장한다.
//
// 동작 원리:
//   OV7670은 PCLK에 동기하여 한 픽셀을 2바이트(RGB565)로 출력한다.
//     1번째 바이트(byte_state=0): RGB565[15:8] → R[4:0], G[5:3]
//     2번째 바이트(byte_state=1): RGB565[7:0]  → G[2:0], B[4:0]
//   2바이트가 모이면 RGB565 → RGB444로 변환 후 we=1과 함께 출력한다.
//
// RGB565 → RGB444 비트 매핑:
//   dout[11:8] = byte0[7:4]               ← R 상위 4bit
//   dout[7:4]  = {byte0[2:0], byte1[7]}   ← G 상위 4bit
//   dout[3:0]  = byte1[4:1]               ← B 상위 4bit
//
// 주요 설계 결정:
//   - d_delayed: OV7670의 PCLK 대비 데이터 셋업 타임을 보상하기 위한
//                1클럭 파이프라인 레지스터. 제거 시 MSB 비트 오류 발생.
//   - h_cnt/v_cnt: 선형 프레임 버퍼 주소 계산에 사용 (addr = v*320 + h)
//   - VSYNC 상승 에지: 프레임 시작 기준, 카운터 전체 리셋
//   - HREF 하강 에지: 한 라인 종료 기준, v_cnt 증가
//==============================================================================

module ov7670_capture (
    input        pclk,
    input        rstn,
    input        vsync,        // 프레임 동기 신호 (상승 에지 = 새 프레임 시작)
    input        href,         // 유효 픽셀 구간 (High = 픽셀 데이터 유효)
    input  [7:0] d,            // OV7670 픽셀 데이터 버스
    output [16:0] addr,        // BRAM 쓰기 주소 (v_cnt * 320 + h_cnt)
    output reg [11:0] dout,    // RGB444 픽셀 출력 {R[3:0], G[3:0], B[3:0]}
    output reg   we            // BRAM 쓰기 인에이블
);

    reg [8:0] h_cnt;           // 수평 픽셀 카운터 (0 ~ 319)
    reg [7:0] v_cnt;           // 수직 라인 카운터  (0 ~ 239)
    reg       byte_state;      // 0: 첫 번째 바이트 수신 대기, 1: 두 번째 바이트 수신 대기
    reg       vsync_prev, href_prev;
    reg [7:0] d_delayed;       // PCLK 셋업 타임 보상용 1클럭 지연 레지스터
    reg [7:0] d_reg_logic;     // 첫 번째 바이트 임시 저장 레지스터

    assign addr = v_cnt * 320 + h_cnt;

    always @(posedge pclk or negedge rstn) begin
        if (!rstn) begin
            h_cnt      <= 0; v_cnt     <= 0;
            byte_state <= 0; we        <= 0;
            vsync_prev <= 0; href_prev <= 0;
            d_delayed  <= 0;
        end else begin
            vsync_prev <= vsync;
            href_prev  <= href;
            d_delayed  <= d;  // 1클럭 지연: OV7670 데이터 안정화

            // VSYNC 상승 에지: 새 프레임 시작 → 픽셀 카운터 초기화
            if (vsync == 1 && vsync_prev == 0) begin
                v_cnt      <= 0;
                h_cnt      <= 0;
                byte_state <= 0;
                we         <= 0;
            end

            if (href) begin
                if (byte_state == 0) begin
                    // 첫 번째 바이트(RGB565 상위): 임시 레지스터에 저장
                    d_reg_logic <= d_delayed;
                    byte_state  <= 1;
                    we          <= 0;
                end else begin
                    // 두 번째 바이트(RGB565 하위): RGB444 조합 및 BRAM 쓰기
                    dout[11:8] <= d_reg_logic[7:4];                 // R[3:0]
                    dout[7:4]  <= {d_reg_logic[2:0], d_delayed[7]}; // G[3:0]
                    dout[3:0]  <= d_delayed[4:1];                   // B[3:0]
                    we         <= 1;
                    byte_state <= 0;
                    if (h_cnt < 319) h_cnt <= h_cnt + 1;
                end
            end else begin
                we         <= 0;
                byte_state <= 0;
                h_cnt      <= 0;
                // HREF 하강 에지: 한 라인 종료 → 수직 카운터 증가
                if (href == 0 && href_prev == 1) begin
                    if (v_cnt < 239) v_cnt <= v_cnt + 1;
                end
            end
        end
    end

endmodule
