from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools/blender'))
import codex_background_model as bg
META={'name':'bg_codex_floor_f01'}
bg.build('floor',hb)
def after_join():bg.pivots(hb)
