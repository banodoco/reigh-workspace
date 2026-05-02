import type {ReactElement} from 'react';

export type TimelineCompositionProps = {
  timeline: Record<string, unknown>;
  assets: Record<string, unknown>;
  theme?: Record<string, unknown>;
};

export const DEFAULT_THEME = {
  visual: {
    canvas: {
      width: 1920,
      height: 1080,
      fps: 30,
    },
  },
};

export const getTimelineDurationInFrames = (): number => 30;

const TimelineComposition = (): ReactElement | null => null;

export default TimelineComposition;
