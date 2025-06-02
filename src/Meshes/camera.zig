const std = @import("std");
const zm = @import("zmath");

pub const Direction = enum {
    Forward,
    Backward,
    Right,
    Left,
    Up,
    Down,
};
pub const Camera = struct {
    position: [3]f32 = .{0.0, 0.0, 0.0},
    forward: [3]f32 = .{0.0, 0.0, 1.0},
    pitch: f32 = 0.0,
    yaw: f32 = 0.0,
    cursor_pos: [2]f32 = .{0.0, 0.0},
    sensitivity : f32 = 0.01,
    speed: f32 = 1.0,
    
    pub fn mouse_rotate(self: *Camera, cursor_pos: [2]f32) void {
        const delta_x = @as(f32, @floatCast(cursor_pos[0] - self.cursor_pos[0]));
        const delta_y = @as(f32, @floatCast(cursor_pos[1] - self.cursor_pos[1]));
        self.cursor_pos[0] = cursor_pos[0];
        self.cursor_pos[1] = cursor_pos[1];

        self.pitch += self.sensitivity*delta_y;
        self.pitch = @min(self.pitch, 0.48 * std.math.pi);
        self.pitch = @max(self.pitch, -0.48 * std.math.pi);
        self.yaw += self.sensitivity*delta_x;
        self.yaw = zm.modAngle(self.yaw);

        const transform = zm.mul(zm.rotationX(self.pitch), zm.rotationY(self.yaw));
        zm.storeArr3(&self.forward, 
            zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform)));
    }

    pub fn translate(self: *Camera, direction: [3]f32, delta_time:f32) void {
        const speed = zm.f32x4s(self.speed);
        const delta_time_mat = zm.f32x4s(delta_time);
        const right = speed * delta_time_mat * 
            zm.normalize3(
                zm.cross3(
                    zm.f32x4(0.0, 1.0, 0.0, 0.0), zm.loadArr3(self.forward)
                )
            );

        const up = speed * delta_time_mat * zm.f32x4(0.0, 1.0, 0.0, 0.0); 

        const forward = speed * delta_time_mat * zm.loadArr3(self.forward);
        const dir = zm.loadArr3(direction); 
        zm.storeArr3(&self.position, zm.loadArr3(self.position) +
                    (forward*zm.f32x4s(dir[0]) + 
                     right*zm.f32x4s(dir[1]) + 
                     up*zm.f32x4s(dir[2])
                    )
        );

    }
};

