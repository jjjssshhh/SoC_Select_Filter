# SoC_Select_Filter

OV7670 카메라로 영상을 촬영하여 VGA 모니터에 실시간 출력하는 FPGA SoC 프로젝트.  
UART로 필터를 실시간 전환할 수 있다. (흑백 / 블러 / 밝기 / 엣지 / 반전)

## 데모

[![Demo](https://img.youtube.com/vi/QpY_T1iv3Es/0.jpg)](https://youtu.be/QpY_T1iv3Es)

## 구성

| 파일 | 설명 |
|---|---|
| `top_main.v` | 최상위 모듈, 클럭/리셋/모듈 연결 |
| `ov7670_init.v` | SCCB 프로토콜로 카메라 레지스터 초기화 |
| `ov7670_capture.v` | PCLK 동기 픽셀 수신, RGB565 → RGB444 변환 |
| `vga_controller.v` | 640×480@60Hz VGA 타이밍 생성 |
| `rst_and.v` | 다중 리셋 조건 AND 조합 |

## 주요 설계 포인트

- **듀얼 클럭**: 24MHz(카메라 MCLK) / 25MHz(VGA) 독립 생성
- **듀얼포트 BRAM**: PCLK 도메인 쓰기 / 25MHz 도메인 읽기로 320×240 프레임 버퍼 구현
- **RGB565 → RGB444**: 1클럭 지연 파이프라인으로 OV7670 셋업타임 보상 후 비트 매핑
- **리셋 전략**: PLL locked + 카메라 init_done 모두 충족 시 캡처 모듈 리셋 해제

## 개발 환경

- **Tool**: Vivado 2024.2
- **Target Board**: Basys3 (Artix-7)
