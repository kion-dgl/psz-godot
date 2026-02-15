// Common types for element components

export interface ElementProps {
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number;
}

export interface StoryMeta {
  title: string;
  description: string;
  states: {
    name: string;
    label: string;
    description?: string;
  }[];
  defaultState: string;
}
