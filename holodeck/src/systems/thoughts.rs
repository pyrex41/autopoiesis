//! System: spawn GPU particle bursts for incoming thoughts.
//!
//! When a thought arrives for an agent, we spawn a bevy_hanabi one-shot
//! ParticleEffect at the agent's position. Color depends on thought type.

use bevy::prelude::*;
use bevy_hanabi::prelude::*;

use crate::protocol::events::ThoughtReceivedEvent;
use crate::protocol::types::ThoughtType;
use crate::systems::agents::AgentEntityMap;

/// Create a one-shot burst effect for a thought event.
fn thought_burst_effect(color: Color) -> EffectAsset {
    let linear = color.to_linear();
    let c = Vec4::new(
        linear.red * 5.0,
        linear.green * 5.0,
        linear.blue * 5.0,
        1.0,
    );

    let writer = ExprWriter::new();

    let init_age = SetAttributeModifier::new(Attribute::AGE, writer.lit(0.0).expr());
    let init_lifetime = SetAttributeModifier::new(
        Attribute::LIFETIME,
        writer.lit(1.5).uniform(writer.lit(2.5)).expr(),
    );

    let init_pos = SetPositionSphereModifier {
        center: writer.lit(Vec3::ZERO).expr(),
        radius: writer.lit(0.3).expr(),
        dimension: ShapeDimension::Surface,
    };

    let init_vel = SetVelocitySphereModifier {
        center: writer.lit(Vec3::ZERO).expr(),
        speed: writer.lit(1.0).uniform(writer.lit(3.0)).expr(),
    };

    let drag = writer.lit(2.0).expr();
    let update_drag = LinearDragModifier::new(drag);

    let mut color_gradient = Gradient::new();
    color_gradient.add_key(0.0, c);
    color_gradient.add_key(0.4, Vec4::new(c.x, c.y, c.z, 0.7));
    color_gradient.add_key(1.0, Vec4::ZERO);

    let mut size_gradient = Gradient::new();
    size_gradient.add_key(0.0, Vec3::splat(0.06));
    size_gradient.add_key(0.3, Vec3::splat(0.08));
    size_gradient.add_key(1.0, Vec3::splat(0.0));

    let spawner = SpawnerSettings::once(30.0.into());

    EffectAsset::new(64, spawner, writer.finish())
        .with_name("thought_burst")
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

fn color_for_thought_type(thought_type: &ThoughtType) -> Color {
    match thought_type {
        ThoughtType::Observation => Color::srgb(0.2, 0.5, 1.0),  // Blue
        ThoughtType::Decision => Color::srgb(1.0, 0.843, 0.0),   // Gold
        ThoughtType::Action => Color::srgb(0.0, 1.0, 0.533),     // Green
        ThoughtType::Reflection => Color::srgb(0.6, 0.2, 1.0),   // Purple
    }
}

/// Spawn a bevy_hanabi one-shot particle effect when a thought is received.
pub fn spawn_thought_particles(
    mut commands: Commands,
    mut effects: ResMut<Assets<EffectAsset>>,
    mut ev_thought: EventReader<ThoughtReceivedEvent>,
    entity_map: Res<AgentEntityMap>,
    transforms: Query<&Transform>,
) {
    for ev in ev_thought.read() {
        let agent_pos = entity_map
            .0
            .get(&ev.agent_id)
            .and_then(|&e| transforms.get(e).ok())
            .map(|t| t.translation)
            .unwrap_or(Vec3::ZERO);

        let color = color_for_thought_type(&ev.thought.thought_type);
        let effect = effects.add(thought_burst_effect(color));

        commands.spawn((
            ParticleEffect::new(effect),
            Transform::from_translation(agent_pos + Vec3::new(0.0, 1.0, 0.0)),
        ));
    }
}
