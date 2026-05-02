import type {ReactElement} from 'react';

export type EffectComponent = (props: Record<string, unknown>) => ReactElement | null;
export type AnimationComponent = (props: Record<string, unknown>) => ReactElement | null;
export type TransitionComponent = (props: Record<string, unknown>) => ReactElement | null;
export type AnimationMeta = Record<string, unknown>;
