globalThis.LOBBY_LAYOUT = {
  "design_size": [
    1920,
    1080
  ],
  "resize": "scale=min(viewport_w/1920,viewport_h/1080); center design canvas; artwork is contained, extra space filled by dark backdrop",
  "logo_mark": [
    170,
    74,
    192,
    192
  ],
  "title_wordmark_rect": [
    375,
    132,
    726,
    86
  ],
  "title_rect": [
    377,
    118,
    690,
    110
  ],
  "title_text": "HEX BLADE",
  "title_font_size": 116,
  "title_italic": true,
  "logo_underline": [
    375,
    242,
    336,
    18
  ],
  "subtitle_rect": [
    372,
    282,
    670,
    36
  ],
  "subtitle": "쿼터뷰 3D 액션 로그라이트",
  "subtitle_font_size": 27,
  "menus": [
    {
      "id": "sector_run",
      "rect": [
        157,
        344,
        624,
        125
      ],
      "title": "섹터 런",
      "subtitle": "HEX SECTOR RUN",
      "title_font_size": 49,
      "subtitle_font_size": 25,
      "existing_handler": "Lobby._start_run"
    },
    {
      "id": "death_test",
      "rect": [
        157,
        484,
        624,
        125
      ],
      "title": "연출 테스트",
      "subtitle": "MAMMOTH B",
      "title_font_size": 49,
      "subtitle_font_size": 25,
      "existing_handler": "Lobby._go(Lobby.DEATH_TEST_SCENE)"
    },
    {
      "id": "test_scenes",
      "rect": [
        157,
        624,
        624,
        125
      ],
      "title": "테스트 씬",
      "subtitle": "",
      "title_font_size": 49,
      "existing_handler": "Lobby._toggle_tests"
    },
    {
      "id": "quit",
      "rect": [
        157,
        764,
        540,
        125
      ],
      "title": "종료",
      "subtitle": "",
      "title_font_size": 49,
      "existing_handler": "get_tree().quit"
    }
  ],
  "text_inset": [
    57,
    20
  ],
  "arrow_inset": [
    72,
    38
  ],
  "hint_rect": [
    161,
    933,
    600,
    66
  ],
  "hint_text": "↑↓ 선택   ENTER 결정",
  "hint_font_size": 25,
  "extra_hint_rect": [
    169,
    1013,
    760,
    34
  ],
  "extra_hint_text": "게임 중 ESC 로비   ·   F11 전체 화면",
  "extra_hint_font_size": 18,
  "drawer_rect": [
    166,
    334,
    760,
    650
  ],
  "drawer_title": "테스트 씬",
  "drawer_row_height": 70,
  "drawer_close": "ESC 닫기",
  "layered": {
    "background": {
      "path": "png/02_hangar_plate.png",
      "rect": [
        0,
        0,
        1920,
        1080
      ]
    },
    "banner": {
      "path": "ui/09_diagonal_backdrop.svg",
      "rect": [
        0,
        0,
        1920,
        1080
      ]
    },
    "mech_shadow": {
      "path": "ui/15_contact_shadow.svg",
      "rect": [
        865,
        917,
        716,
        86
      ]
    },
    "sword_reflection": {
      "path": "ui/16_sword_floor_light.svg",
      "rect": [
        541,
        935,
        324,
        53
      ]
    },
    "mech": {
      "path": "png/03_mech_cutout.png",
      "rect": [
        135.889,
        125.37,
        1569.973,
        883.579
      ],
      "visual_target": [
        619,
        208,
        1000,
        754
      ],
      "scale": 0.938979,
      "fit": "alpha16 bounding box, uniform fit"
    },
    "drone_shadow": {
      "path": "ui/15_contact_shadow.svg",
      "rect": [
        1511,
        911,
        373,
        48
      ]
    },
    "drone": {
      "path": "png/04_drone_cutout.png",
      "rect": [
        1498.551,
        599.52,
        391.711,
        391.711
      ],
      "visual_target": [
        1510,
        647,
        371,
        298
      ],
      "scale": 0.312369,
      "fit": "alpha16 bounding box, uniform fit"
    },
    "readability": {
      "path": "ui/14_left_readability.svg",
      "rect": [
        0,
        0,
        1920,
        1080
      ]
    }
  },
  "static": {
    "path": "png/01_keyart_clean.png",
    "rect": [
      0,
      0,
      1920,
      1080
    ]
  },
  "palette": {
    "lime": "#82ff43",
    "ink": "#102019",
    "cream": "#f5eedb",
    "navy": "#191728",
    "secondary_text": "#a7b8d5",
    "brand_mint": "#10efd0"
  },
  "motion_suggestion": {
    "bg_parallax_px": 2,
    "mech_parallax_px": 4,
    "drone_parallax_px": 6,
    "drone_idle_vertical_px": 1.5,
    "drone_idle_period_s": 3.0,
    "menu_focus_duration_s": 0.12,
    "menu_focus_translation_px": 6,
    "reduced_motion": true
  }
};
