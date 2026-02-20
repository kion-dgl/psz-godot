import { useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import type { AnimatedTextureInfo } from './tabs/TextureTab';

interface TextureAnimatorProps {
  animatedTextures: AnimatedTextureInfo[];
}

/**
 * Component that animates texture offsets each frame.
 * Used for scrolling effects like waterfalls.
 */
export default function TextureAnimator({ animatedTextures }: TextureAnimatorProps) {
  // Store base offsets for each texture (the initial offset before animation)
  const baseOffsetsRef = useRef<Map<string, { x: number; y: number }>>(new Map());

  useFrame((_, delta) => {
    animatedTextures.forEach(({ key, texture, scrollX, scrollY }) => {
      // Initialize base offset if not set
      if (!baseOffsetsRef.current.has(key)) {
        baseOffsetsRef.current.set(key, {
          x: texture.offset.x,
          y: texture.offset.y,
        });
      }

      // Update offset based on scroll speed
      texture.offset.x += scrollX * delta;
      texture.offset.y += scrollY * delta;

      // Wrap offset to prevent floating point issues over time
      if (texture.offset.x > 10) texture.offset.x -= 10;
      if (texture.offset.x < -10) texture.offset.x += 10;
      if (texture.offset.y > 10) texture.offset.y -= 10;
      if (texture.offset.y < -10) texture.offset.y += 10;
    });
  });

  // This component doesn't render anything
  return null;
}
