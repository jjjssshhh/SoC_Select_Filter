`timescale 1ns / 1ps
//==============================================================================
// 모듈명 : vga_controller
// 기  능 : 640×480@60Hz VGA 타이밍을 생성하고, 프레임 버퍼에서 읽은
//          320×240 카메라 영상을 화면 중앙에 출력한다.
//
// VGA 타이밍 (픽셀 클럭 25MHz 기준):
//   수평: 640(가시) + 16(FP) + 96(Sync) + 48(BP) = 800 픽셀/라인
//   수직: 480(가시) + 10(FP) +  2(Sync) + 33(BP) = 525 라인/프레임
//
// 이미지 배치:
//   320×240 영상을 640×480 화면 중앙에 표시.
//   수평 시작점 H_START = (640 - 320) / 2 = 160
//   수직 시작점 V_START = (480 - 240) / 2 = 120
//
// 주요 설계 결정:
//   - 픽셀 출력 윈도우를 수평으로 +3 픽셀 오프셋 적용.
//     BRAM 읽기 레이턴시로 인해 이미지 좌측 경계에서 노이즈 라인이 발생하며,
//     출력 윈도우를 3픽셀 우측으로 이동하여 해당 아티팩트를 마스킹한다.
//   - 주소 카운터와 픽셀 출력은 별도 always 블록으로 분리.
//     주소는 이미지 영역 진입 즉시 증가하고, 출력은 +3 오프셋 후 시작하여
//     BRAM의 1~2클럭 읽기 지연에 맞게 데이터가 정렬된다.
//==============================================================================

module vga_controller (
    input             clk_25M,
    input             rstn,
    output reg        hsync,
    output reg        vsync,
    output reg [3:0]  r, g, b,
    output reg [16:0] rd_addr,     // 프레임 버퍼 읽기 주소
    input      [11:0] pixel_data   // BRAM에서 읽은 RGB444 픽셀
);

    // --- VGA 타이밍 파라미터 ---
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = 525;

    // --- 이미지 배치 파라미터 ---
    localparam IMG_W   = 320;
    localparam IMG_H   = 240;
    localparam H_START = (H_VISIBLE - IMG_W) / 2;  // 160: 수평 중앙 정렬
    localparam V_START = (V_VISIBLE - IMG_H) / 2;  // 120: 수직 중앙 정렬

    reg [9:0] h_cnt, v_cnt;

    // --- 픽셀/라인 카운터 ---
    always @(posedge clk_25M or negedge rstn) begin
        if (!rstn) begin h_cnt <= 0; v_cnt <= 0; end
        else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 0;
                if (v_cnt == V_TOTAL - 1) v_cnt <= 0;
                else v_cnt <= v_cnt + 1;
            end else h_cnt <= h_cnt + 1;
        end
    end

    // --- 동기 신호 생성 (Active Low) ---
    always @(posedge clk_25M) begin
        hsync <= (h_cnt >= (H_VISIBLE + H_FRONT) &&
                  h_cnt <  (H_VISIBLE + H_FRONT + H_SYNC)) ? 0 : 1;
        vsync <= (v_cnt >= (V_VISIBLE + V_FRONT) &&
                  v_cnt <  (V_VISIBLE + V_FRONT + V_SYNC)) ? 0 : 1;
    end

    // --- 프레임 버퍼 읽기 주소 생성 ---
    always @(posedge clk_25M or negedge rstn) begin
        if (!rstn) rd_addr <= 0;
        else begin
            if (h_cnt < H_VISIBLE && v_cnt < V_VISIBLE) begin
                if (h_cnt >= H_START && h_cnt < H_START + IMG_W &&
                    v_cnt >= V_START && v_cnt < V_START + IMG_H) begin
                    if (rd_addr == (IMG_W * IMG_H) - 1) rd_addr <= 0;
                    else rd_addr <= rd_addr + 1;
                end else if (v_cnt == 0 && h_cnt == 0) rd_addr <= 0;
            end
        end
    end

    // --- 픽셀 출력 ---
    // 수평 +3 오프셋: BRAM 읽기 레이턴시로 발생하는 좌측 경계 노이즈 마스킹
    always @(posedge clk_25M) begin
        if (h_cnt < H_VISIBLE && v_cnt < V_VISIBLE &&
            h_cnt >= H_START + 3 && h_cnt < H_START + IMG_W + 3 &&
            v_cnt >= V_START     && v_cnt < V_START + IMG_H) begin
            {r, g, b} <= pixel_data;
        end else begin
            {r, g, b} <= 12'h000;  // 이미지 영역 외 블랙 출력
        end
    end

endmodule
