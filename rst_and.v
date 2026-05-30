`timescale 1ns / 1ps
//==============================================================================
// 모듈명 : rst_and
// 기  능 : 여러 리셋 조건을 AND하여 두 종류의 리셋 신호를 생성한다.
//
// rstn_basic   : rstn & locked
//   PLL이 안정화(locked)된 이후에만 해제. 대부분의 모듈에 사용.
//
// rstn_capture : rstn & locked & init_done
//   PLL 안정화 + 카메라 레지스터 초기화 완료 이후에만 해제.
//   초기화 전 ov7670_capture가 동작하면 쓰레기 픽셀이 BRAM에 기록되므로
//   init_done을 추가 조건으로 삽입하여 캡처 시작 시점을 제어한다.
//==============================================================================

module rst_and (
    input  rstn,
    input  locked,
    input  init_done,
    output rstn_capture,
    output rstn_basic
);
    assign rstn_basic   = rstn & locked;
    assign rstn_capture = rstn & locked & init_done;
endmodule
