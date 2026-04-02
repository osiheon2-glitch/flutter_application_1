from ursina import *
from ursina.prefabs.first_person_controller import FirstPersonController
import random

app = Ursina()

# --- [게임 데이터] ---
timer = 180
oni_hp = 5
game_active = False
player_shoot_cooldown = 0
ROLE_COLORS = {'CITIZEN': color.green, 'SHERIFF': color.blue, 'ONI': color.red, 'DEAD': color.gray}

roles_pool = ['CITIZEN', 'SHERIFF', 'ONI']
my_role = random.choice(roles_pool)

# --- [맵 및 경계] ---
floor = Entity(model='plane', texture='white_cube', color=color.rgb(200,180,100), scale=(100,1,100), collider='box')
# 외곽 벽 (탈출 방지)
bound_walls = [
    Entity(model='cube', position=(0, 5, 50), scale=(100, 20, 5), color=color.clear, collider='box'),
    Entity(model='cube', position=(0, 5, -50), scale=(100, 20, 5), color=color.clear, collider='box'),
    Entity(model='cube', position=(50, 5, 0), scale=(5, 20, 100), color=color.clear, collider='box'),
    Entity(model='cube', position=(-50, 5, 0), scale=(5, 20, 100), color=color.clear, collider='box')
]

for i in range(15):
    Entity(model='cube', texture='white_cube', color=color.orange, scale=(10,5,2), 
           position=(random.randint(-30,30), 2.5, random.randint(-30,30)), collider='box')

# --- [플레이어 설정] ---
player = FirstPersonController(model='cube', y=2, z=-10, color=ROLE_COLORS[my_role])
player.speed = 6.0 if my_role == 'ONI' else (5.5 if my_role == 'SHERIFF' else 5.0)

# 보안관이 들고 있는 총 모델
gun_model = Entity(model='cube', parent=camera.ui, scale=(0.1, 0.05, 0.3), position=(0.5, -0.3), color=color.black, visible=(my_role == 'SHERIFF'))
# 바닥에 떨어질 총 아이템
dropped_gun = Entity(model='cube', color=color.black, scale=(0.6, 0.2, 0.2), visible=False, collider='box')

# --- [UI] ---
timer_text = Text(text="", parent=camera.ui, position=(-0.8, 0.45), scale=2, visible=False)
hp_text = Text(text=f"ONI HP: {oni_hp}", parent=camera.ui, position=(0.6, 0.45), scale=2, color=color.red, visible=False)
cooldown_text = Text(text="", parent=camera.ui, position=(0, -0.4), scale=2, color=color.orange)
info_text = Text(text=f"ROLE: {my_role}", parent=camera.ui, origin=(0,0), scale=3, background=True)

npcs = []

class AI_NPC(Entity):
    def __init__(self, role_name, position, speed):
        super().__init__(model='cube', color=ROLE_COLORS[role_name], scale=(1, 2, 1), position=position, collider='box', role=role_name)
        self.speed = speed
        self.move_dir = Vec3(random.uniform(-1,1), 0, random.uniform(-1,1)).normalized()
        self.change_dir_timer = random.uniform(2, 5)
        self.shoot_cooldown = random.uniform(0, 4)
        npcs.append(self)

    def safe_move(self, direction):
        if not raycast(self.world_position + Vec3(0,1,0), direction, distance=1.5, ignore=(self, floor)).hit:
            self.position += direction * self.speed * time.dt
            return True
        return False

def spawn_npcs():
    counts = {'CITIZEN': 4, 'SHERIFF': 1, 'ONI': 1}
    if my_role in counts: counts[my_role] -= 1
    for role, count in counts.items():
        for _ in range(count):
            speed = 6.0 if role == 'ONI' else (5.5 if role == 'SHERIFF' else 5.0)
            AI_NPC(role, (random.randint(-30,30), 1, random.randint(-30,30)), speed)

def start_game():
    global game_active
    info_text.visible = False; timer_text.visible = True
    if my_role == 'ONI' or any(n.role == 'ONI' for n in npcs): hp_text.visible = True
    game_active = True
    spawn_npcs()

invoke(start_game, delay=3)

def shoot_bullet(from_pos, target_pos):
    bullet = Entity(model='sphere', color=color.yellow, scale=0.2, position=from_pos)
    bullet.look_at(target_pos)
    bullet.animate_position(target_pos, duration=0.2, curve=curve.linear)
    destroy(bullet, delay=0.2)

# --- [사망 처리 및 총 드롭 핵심 로직] ---
def handle_death(target):
    global my_role
    # 보안관(플레이어 혹은 AI)이 죽을 때 총을 그 자리에 생성
    if hasattr(target, 'role') and target.role == 'SHERIFF':
        dropped_gun.world_position = target.world_position + Vec3(0, 0.5, 0)
        dropped_gun.visible = True
        print("보안관 사망: 총이 떨어졌습니다!")
    elif target == player and my_role == 'SHERIFF':
        dropped_gun.world_position = player.world_position + Vec3(0, 0.5, 0)
        dropped_gun.visible = True
        gun_model.visible = False
        print("당신(보안관)이 죽었습니다: 총이 떨어졌습니다!")

    if target == player:
        my_role = 'DEAD'
        player.color = color.gray
    else:
        target.role = 'DEAD'
        target.color = color.gray

def update():
    global timer, game_active, oni_hp, my_role, player_shoot_cooldown
    if not game_active: return

    timer -= time.dt; timer_text.text = f"TIME: {int(timer)}"; hp_text.text = f"ONI HP: {oni_hp}"
    if player_shoot_cooldown > 0:
        player_shoot_cooldown -= time.dt
        cooldown_text.text = f"RELOADING: {player_shoot_cooldown:.1f}s"
    else: cooldown_text.text = ""

    if timer <= 0: finish_game("SURVIVORS WIN!")
    if oni_hp <= 0: finish_game("SHERIFF WIN!")

    survivors = [n for n in npcs if n.role in ['CITIZEN', 'SHERIFF']]
    if my_role in ['CITIZEN', 'SHERIFF']: survivors.append(player)
    if not survivors: finish_game("ONI WIN!")

    for n in npcs:
        if n.role == 'DEAD': continue
        
        # 시민 AI: 총이 떨어지면 최우선 순위로 이동
        if n.role == 'CITIZEN' and dropped_gun.visible:
            n.look_at(dropped_gun)
            n.safe_move(n.forward)
            if distance(n, dropped_gun) < 1.5:
                n.role = 'SHERIFF'; n.color = color.blue; n.speed = 5.5; dropped_gun.visible = False
            continue

        if n.role == 'ONI':
            closest = None; min_dist = 999
            for s in survivors:
                d = distance(n, s)
                if d < min_dist: min_dist, closest = d, s
            if closest:
                n.look_at(closest)
                if not n.safe_move(n.forward):
                    n.move_dir = Vec3(random.uniform(-1,1), 0, random.uniform(-1,1)).normalized()
                if distance(n, closest) < 1.5: handle_death(closest)

        elif n.role == 'SHERIFF':
            n.shoot_cooldown -= time.dt
            if n.shoot_cooldown <= 0:
                oni_targets = [x for x in npcs if x.role == 'ONI'] + ([player] if my_role == 'ONI' else [])
                citizen_targets = [x for x in npcs if x.role == 'CITIZEN'] + ([player] if my_role == 'CITIZEN' else [])
                if random.random() < 0.10 and citizen_targets:
                    t = random.choice(citizen_targets)
                    if distance(n, t) < 15:
                        shoot_bullet(n.position + Vec3(0,1,0), t.position); handle_death(t); handle_death(n)
                        n.shoot_cooldown = 4.0
                elif oni_targets:
                    t = random.choice(oni_targets)
                    if distance(n, t) < 15:
                        shoot_bullet(n.position + Vec3(0,1,0), t.position)
                        if random.random() < 0.40: oni_hp -= 1
                        n.shoot_cooldown = 4.0
            n.safe_move(n.move_dir)

        else:
            n.change_dir_timer -= time.dt
            if not n.safe_move(n.move_dir) or n.change_dir_timer <= 0:
                n.move_dir = Vec3(random.uniform(-1,1), 0, random.uniform(-1,1)).normalized()
                n.change_dir_timer = random.uniform(2, 5)

    if my_role == 'ONI':
        for n in npcs:
            if n.role != 'DEAD' and distance(player, n) < 2: handle_death(n)

    if dropped_gun.visible and distance(player, dropped_gun) < 2 and my_role == 'CITIZEN':
        my_role = 'SHERIFF'; player.color = color.blue; gun_model.visible = True; dropped_gun.visible = False; player.speed = 5.5

def input(key):
    global player_shoot_cooldown, oni_hp, my_role
    if key == 'left mouse down' and my_role == 'SHERIFF' and game_active and player_shoot_cooldown <= 0:
        target_ent = mouse.hovered_entity
        target_point = mouse.world_point if target_ent else player.position + player.forward * 50
        shoot_bullet(player.position + Vec3(0,1,0), target_point)
        if target_ent and hasattr(target_ent, 'role'):
            if target_ent.role == 'ONI': oni_hp -= 1
            elif target_ent.role == 'CITIZEN': handle_death(target_ent); handle_death(player)
        player_shoot_cooldown = 3.0

def finish_game(msg):
    global game_active
    game_active = False
    Text(text=msg, parent=camera.ui, origin=(0,0), scale=3, color=color.yellow, background=True)
    invoke(application.quit, delay=5)

app.run()