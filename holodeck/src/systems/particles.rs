//! Particle effect presets using bevy_hanabi.
//!
//! Provides factory functions for common particle effects used throughout
//! the holodeck: idle ambient particles, active bursts, error explosions,
//! and completion celebrations.

use bevy::prelude::*;
use bevy_hanabi::prelude::*;

use crate::protocol::events::AgentStateChangedEvent;
use crate::protocol::types::AgentState;
use crate::state::components::{AgentNode, AgentParticles};
use crate::systems::agents::AgentEntityMap;

/// Holds pre-built particle effect asset handles for reuse.
#[derive(Resource)]
pub struct ParticlePresets {
    pub idle: Handle<EffectAsset>,
    pub active: Handle<EffectAsset>,
    pub error_burst: Handle<EffectAsset>,
    pub completion: Handle<EffectAsset>,
}

/// Slow ambient particles drifting upward from an agent. Subtle idle state indicator.
pub fn idle_particles(color: Color) -> EffectAsset {
    let linear = color.to_linear();
    let c = Vec4::new(linear.red * 2.0, linear.green * 2.0, linear.blue * 2.0, 1.0);

    let writer = ExprWriter::new();

    let init_age = SetAttributeModifier::new(Attribute::AGE, writer.lit(0.0).expr());
    let init_lifetime = SetAttributeModifier::new(
        Attribute::LIFETIME,
        writer.lit(6.0).uniform(writer.lit(8.0)).expr(),
    );

    let init_pos = SetPositionSphereModifier {
        center: writer.lit(Vec3::ZERO).expr(),
        radius: writer.lit(1.0).expr(),
        dimension: ShapeDimension::Surface,
    };

    // Gentle upward drift
    let vel = writer.lit(Vec3::new(0.0, 0.3, 0.0)).expr();
    let init_vel = SetAttributeModifier::new(Attribute::VELOCITY, vel);

    let drag = writer.lit(0.5).expr();
    let update_drag = LinearDragModifier::new(drag);

    let mut color_gradient = Gradient::new();
    color_gradient.add_key(0.0, Vec4::new(c.x, c.y, c.z, 0.0));
    color_gradient.add_key(0.2, Vec4::new(c.x, c.y, c.z, 0.6));
    color_gradient.add_key(0.8, Vec4::new(c.x, c.y, c.z, 0.3));
    color_gradient.add_key(1.0, Vec4::ZERO);

    let mut size_gradient = Gradient::new();
    size_gradient.add_key(0.0, Vec3::splat(0.02));
    size_gradient.add_key(0.5, Vec3::splat(0.05));
    size_gradient.add_key(1.0, Vec3::splat(0.0));

    EffectAsset::new(64, SpawnerSettings::rate(8.0.into()), writer.finish())
        .with_name("idle_particles")
        .init(init_pos)
        .init(init_vel)
        .init(init_age)
        .init(init_lifetime)
        .update(update_drag)
        .render(ColorOverLifetimeModifier {
            gradient: color_gradient,
            blend: ColorBlendMode::Overwrite,
            mask: ColorBlendMask::RGBA,
        })
        .render(SizeOverLifetimeModifier {
            gradient: size_gradient,
            screen_space_size: false,
        })
}

/// Energetic outward burst for active/running agents.
pub fn active_particles(color: Color) -> EffectAsset {
    let linear = color.to_linear();
    let c = Vec4::new(linear.red * 4.0, linear.green * 4.0, linear.blue * 4.0, 1.0);

    let writer = ExprWriter::new();

    let init_age = SetAttributeModifier::new(Attribute::AGE, writer.lit(0.0).expr());
    let init_lifetime = SetAttributeModifier::new(
        Attribute::LIFETIME,
        writer.lit(1.0).uniform(writer.lit(1.5)).expr(),
    );

    let init_pos = SetPositionSphereModifier {
        center: writer.lit(Vec3::ZERO).expr(),
        radius: writer.lit(0.5).expr(),
        dimension: ShapeDimension::Volume,
    };

    let init_vel = SetVelocitySphereModifier {
        center: writer.lit(Vec3::ZERO).expr(),
        speed: writer.lit(2.0).uniform(writer.lit(4.0)).expr(),
    };

    let drag = writer.lit(3.0).expr();
    let update_drag = LinearDragModifier::new(drag);

    let mut color_gradient = Gradient::new();
    color_gradient.add_key(0.0, c);
    color_gradient.add_key(0.3, Vec4::new(c.x, c.y, c.z, 0.8));
    color_gradient.add_key(1.0, Vec4::ZERO);

    let mut size_gradient = Gradient::new();
    size_gradient.add_key(0.0, Vec3::splat(0.06));
    size_gradient.add_key(0.3, Vec3::splat(0.04));
    size_gradient.add_key(1.0, Vec3::splat(0.0));

    EffectAsset::new(256, SpawnerSettings::rate(80.0.into()), writer.finish())
        .with_name("active_particles")
        .init(init_pos)
        .init(init_vel)
        .init(init_age)
        .init(init_lifetime)
        .update(update_drag)
        .render(ColorOverLifetimeModifier {
            gradient: color_gradient,
            blend: ColorBlendMode::Overwrite,
            mask: ColorBlendMask::RGBA,
        })
        .render(SizeOverLifetimeModifier {
            gradient: size_gradient,
            screen_space_size: false,
        })
}

/// One-shot explosive error burst -- red/orange particles with gravity.
pub fn error_burst(color: Color) -> EffectAsset {
    let linear = color.to_linear();
    let c = Vec4::new(linear.red * 6.0, linear.green * 6.0, linear.blue * 6.0, 1.0);

    let writer = ExprWriter::new();

    let init_age = SetAttributeModifier::new(Attribute::AGE, writer.lit(0.0).expr());
    let init_lifetime = SetAttributeModifier::new(
        Attribute::LIFETIME,
        writer.lit(0.3).uniform(writer.lit(0.5)).expr(),
    );

    let init_pos = SetPositionSphereModifier {
        center: writer.lit(Vec3::ZERO).expr(),
        radius: writer.lit(0.3).expr(),
        dimension: ShapeDimension::Volume,
    };

    // Explosive outward velocity
    let init_vel = SetVelocitySphereModifier {
        center: writer.lit(Vec3::ZERO).expr(),
        speed: writer.lit(8.0).uniform(writer.lit(15.0)).expr(),
    };

    // Gravity pulls particles down
    let accel = writer.lit(Vec3::new(0.0, -20.0, 0.0)).expr();
    let update_accel = AccelModifier::new(accel);

    let drag = writer.lit(2.0).expr();
    let update_drag = LinearDragModifier::new(drag);

    let mut color_gradient = Gradient::new();
    color_gradient.add_key(0.0, c);
    color_gradient.add_key(0.5, Vec4::new(c.x * 0.5, c.y * 0.2, 0.0, 0.8));
    color_gradient.add_key(1.0, Vec4::ZERO);

    let mut size_gradient = Gradient::new();
    size_gradient.add_key(0.0, Vec3::splat(0.1));
    size_gradient.add_key(1.0, Vec3::splat(0.0));

    let spawner = SpawnerSettings::once(200.0.into());

    EffectAsset::new(256, spawner, writer.finish())
        .with_name("error_burst")
        .init(init_pos)
        .init(init_vel)
        .init(init_age)
        .init(init_lifetime)
        .update(update_accel)
        .update(update_drag)
        .render(ColorOverLifetimeModifier {
            gradient: color_gradient,
            blend: ColorBlendMode::Overwrite,
            mask: ColorBlendMask::RGBA,
        })
        .render(SizeOverLifetimeModifier {
            gradient: size_gradient,
            screen_space_size: false,
        })
}

/// One-shot gold upward fountain for task completion celebration.
pub fn completion_burst() -> EffectAsset {
    let gold = Vec4::new(4.0, 3.4, 0.0, 1.0);

    let writer = ExprWriter::new();

    let init_age = SetAttributeModifier::new(Attribute::AGE, writer.lit(0.0).expr());
    let init_lifetime = SetAttributeModifier::new(
        Attribute::LIFETIME,
        writer.lit(1.0).uniform(writer.lit(2.0)).expr(),
    );

    let init_pos = SetPositionSphereModifier {
        center: writer.lit(Vec3::ZERO).expr(),
        radius: writer.lit(0.2).expr(),
        dimension: ShapeDimension::Volume,
    };

    // Upward fountain with outward spread
    let init_vel = SetVelocitySphereModifier {
        center: writer.lit(Vec3::new(0.0, -2.0, 0.0)).expr(),
        speed: writer.lit(4.0).uniform(writer.lit(8.0)).expr(),
    };

    // Light gravity
    let accel = writer.lit(Vec3::new(0.0, -6.0, 0.0)).expr();
    let update_accel = AccelModifier::new(accel);

    let drag = writer.lit(1.0).expr();
    let update_drag = LinearDragModifier::new(drag);

    let mut color_gradient = Gradient::new();
    color_gradient.add_key(0.0, gold);
    color_gradient.add_key(0.3, Vec4::new(4.0, 3.0, 0.5, 1.0));
    color_gradient.add_key(0.7, Vec4::new(2.0, 1.5, 0.0, 0.6));
    color_gradient.add_key(1.0, Vec4::ZERO);

    let mut size_gradient = Gradient::new();
    size_gradient.add_key(0.0, Vec3::splat(0.04));
    size_gradient.add_key(0.3, Vec3::splat(0.08));
    size_gradient.add_key(1.0, Vec3::splat(0.0));

    let spawner = SpawnerSettings::once(150.0.into());

    EffectAsset::new(256, spawner, writer.finish())
        .with_name("completion_burst")
        .init(init_pos)
        .init(init_vel)
        .init(init_age)
        .init(init_lifetime)
        .update(update_accel)
        .update(update_drag)
        .render(ColorOverLifetimeModifier {
            gradient: color_gradient,
            blend: ColorBlendMode::Overwrite,
            mask: ColorBlendMask::RGBA,
        })
        .render(SizeOverLifetimeModifier {
            gradient: size_gradient,
            screen_space_size: false,
        })
}

/// Startup system: create particle preset assets and store handles in resource.
pub fn init_particle_presets(mut commands: Commands, mut effects: ResMut<Assets<EffectAsset>>) {
    let default_color = Color::srgb(0.0, 0.8, 1.0); // Cyan
    let error_color = Color::srgb(1.0, 0.2, 0.2); // Red

    commands.insert_resource(ParticlePresets {
        idle: effects.add(idle_particles(default_color)),
        active: effects.add(active_particles(default_color)),
        error_burst: effects.add(error_burst(error_color)),
        completion: effects.add(completion_burst()),
    });
}

/// Attach persistent particle emitters to agents that don't have one yet.
pub fn attach_agent_particles(
    mut commands: Commands,
    presets: Option<Res<ParticlePresets>>,
    agents_without_particles: Query<(Entity, &AgentNode), Without<AgentParticles>>,
) {
    let Some(presets) = presets else { return };

    for (entity, agent) in agents_without_particles.iter() {
        let effect_handle = preset_for_state(&agent.state, &presets);
        let effect_entity = commands
            .spawn((ParticleEffect::new(effect_handle), Transform::default()))
            .id();

        // Make it a child of the agent
        commands.entity(entity).add_child(effect_entity);
        commands
            .entity(entity)
            .insert(AgentParticles { effect_entity });
    }
}

/// Switch particle preset when agent state changes.
pub fn update_agent_particles(
    mut commands: Commands,
    presets: Option<Res<ParticlePresets>>,
    mut ev_state: EventReader<AgentStateChangedEvent>,
    entity_map: Res<AgentEntityMap>,
    agents: Query<&AgentParticles>,
    mut effects: Query<&mut ParticleEffect>,
) {
    let Some(presets) = presets else { return };

    for ev in ev_state.read() {
        let Some(&agent_entity) = entity_map.0.get(&ev.agent_id) else {
            continue;
        };
        let Ok(agent_particles) = agents.get(agent_entity) else {
            continue;
        };

        let new_handle = preset_for_state(&ev.state, &presets);

        // For error state, also trigger a one-shot error burst
        if ev.state == AgentState::Stopped {
            // Spawn a one-shot error burst at the agent position
            let burst_handle = presets.error_burst.clone();
            commands.entity(agent_entity).with_children(|parent| {
                parent.spawn((ParticleEffect::new(burst_handle), Transform::default()));
            });
        }

        // Update the persistent emitter's effect handle
        if let Ok(mut effect) = effects.get_mut(agent_particles.effect_entity) {
            *effect = ParticleEffect::new(new_handle);
        }
    }
}

fn preset_for_state(state: &AgentState, presets: &ParticlePresets) -> Handle<EffectAsset> {
    match state {
        AgentState::Initialized | AgentState::Paused => presets.idle.clone(),
        AgentState::Running => presets.active.clone(),
        AgentState::Stopped => presets.idle.clone(), // Will also get error burst
    }
}
