import { useState } from 'react';
import { ALL_CLASSES } from '../character-creator/data/classData';
import PsoListView from './PsoListView';
import MatrixView from './MatrixView';
import CarouselView from './CarouselView';
import SlatsView from './SlatsView';
import CardGridView from './CardGridView';
import TypeFirstView from './TypeFirstView';
import {
  LIGHT_SLATS_PALETTE,
  SKY_SLATS_PALETTE,
  STEEL_SLATS_PALETTE,
  PSZ_SLATS_PALETTE,
} from './slatsPalettes';
import type { VariantId } from './types';

const CANVAS_W = 1280;
const CANVAS_H = 720;

const VARIANTS: { id: VariantId; label: string; tagline: string }[] = [
  {
    id: 'pso-list',
    label: 'PSO PC V2 list',
    tagline: 'vertical class list + portrait + stats — literal #168 reading',
  },
  {
    id: 'matrix',
    label: 'Race × Type matrix',
    tagline: '3×3 grid: race rows × type columns, M/F portraits per cell',
  },
  {
    id: 'carousel',
    label: 'Hero carousel',
    tagline: 'one hero card + prev/next + thumbnail strip',
  },
  {
    id: 'slats',
    label: 'Slats · dark',
    tagline: 'original slats (PSO red/green/blue type colours on dark navy)',
  },
  {
    id: 'slats-light',
    label: 'Slats · light',
    tagline: 'PSZ palette A: cream → sky gradient bg, gold/slate/sky type tints, navy text',
  },
  {
    id: 'slats-sky',
    label: 'Slats · sky',
    tagline: 'PSZ palette B: full sky-blue gradient bg, yellow/silver/pale-sky type tints',
  },
  {
    id: 'slats-steel',
    label: 'Slats · steel',
    tagline: 'PSZ palette C: charcoal/slate bg, gold/silver/sky type tints, white text',
  },
  {
    id: 'slats-psz',
    label: 'Slats · PSZ theme',
    tagline:
      'sky-blue bg + dark navy info panel + steel-blue borders + gold confirm — mirrors themes/rpg_theme.tres',
  },
  {
    id: 'cards',
    label: 'TCG card grid',
    tagline: '7×2 grid of PSO Episode 3-flavoured class cards with metallic borders',
  },
  {
    id: 'type-first',
    label: 'Type-first',
    tagline: 'pick Hunter / Ranger / Force first, then race row within that type',
  },
];

export default function CharacterSelect() {
  const [variant, setVariant] = useState<VariantId>('pso-list');
  const [selectedId, setSelectedId] = useState<string>('humar');

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        background: '#0a0a1a',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        padding: 16,
        gap: 10,
        overflow: 'auto',
        boxSizing: 'border-box',
        fontFamily: 'system-ui, sans-serif',
        color: '#e0e0e0',
      }}
    >
      {/* Variant switcher */}
      <div
        style={{
          width: CANVAS_W,
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          padding: '8px 12px',
          background: '#12122a',
          border: '1px solid #2a2a4a',
          borderRadius: 4,
          flexShrink: 0,
        }}
      >
        <span
          style={{
            fontSize: 11,
            color: '#666',
            letterSpacing: '0.15em',
            textTransform: 'uppercase',
            marginRight: 4,
          }}
        >
          Variant
        </span>
        {VARIANTS.map((v) => {
          const active = v.id === variant;
          return (
            <button
              key={v.id}
              type="button"
              onClick={() => setVariant(v.id)}
              style={{
                background: active ? '#1f1f3f' : 'transparent',
                color: active ? '#fde047' : '#aab',
                border: `1px solid ${active ? '#fde047' : '#2a2a4a'}`,
                borderRadius: 4,
                padding: '4px 10px',
                fontSize: 12,
                cursor: 'pointer',
                fontFamily: 'inherit',
              }}
            >
              {v.label}
            </button>
          );
        })}
        <span style={{ flex: 1 }} />
        <span style={{ fontSize: 11, color: '#888' }}>{CANVAS_W} × {CANVAS_H}</span>
        <span style={{ fontSize: 11, color: '#888' }}>
          selected: <code style={{ color: '#fde047' }}>{selectedId}</code>
        </span>
        <button
          type="button"
          onClick={() => setSelectedId('humar')}
          style={{
            background: '#1e3a8a',
            color: '#fde047',
            border: '1px solid #fde047',
            borderRadius: 4,
            padding: '4px 10px',
            fontSize: 11,
            cursor: 'pointer',
          }}
        >
          Reset
        </button>
      </div>

      {/* Tagline */}
      <div
        style={{
          width: CANVAS_W,
          fontSize: 11,
          color: '#888',
          fontFamily: '"Share Tech Mono", monospace',
          paddingLeft: 4,
          flexShrink: 0,
        }}
      >
        {VARIANTS.find((v) => v.id === variant)?.tagline}
      </div>

      {/* Fixed-size design frame */}
      <div
        style={{
          width: CANVAS_W,
          height: CANVAS_H,
          flexShrink: 0,
          position: 'relative',
          overflow: 'hidden',
          boxShadow: '0 0 0 1px #2a2a4a, 0 8px 32px rgba(0,0,0,0.5)',
        }}
      >
        {variant === 'pso-list' && (
          <PsoListView classes={ALL_CLASSES} selectedId={selectedId} onSelect={setSelectedId} />
        )}
        {variant === 'matrix' && (
          <MatrixView classes={ALL_CLASSES} selectedId={selectedId} onSelect={setSelectedId} />
        )}
        {variant === 'carousel' && (
          <CarouselView classes={ALL_CLASSES} selectedId={selectedId} onSelect={setSelectedId} />
        )}
        {variant === 'slats' && (
          <SlatsView classes={ALL_CLASSES} selectedId={selectedId} onSelect={setSelectedId} />
        )}
        {variant === 'slats-light' && (
          <SlatsView
            classes={ALL_CLASSES}
            selectedId={selectedId}
            onSelect={setSelectedId}
            palette={LIGHT_SLATS_PALETTE}
          />
        )}
        {variant === 'slats-sky' && (
          <SlatsView
            classes={ALL_CLASSES}
            selectedId={selectedId}
            onSelect={setSelectedId}
            palette={SKY_SLATS_PALETTE}
          />
        )}
        {variant === 'slats-steel' && (
          <SlatsView
            classes={ALL_CLASSES}
            selectedId={selectedId}
            onSelect={setSelectedId}
            palette={STEEL_SLATS_PALETTE}
          />
        )}
        {variant === 'slats-psz' && (
          <SlatsView
            classes={ALL_CLASSES}
            selectedId={selectedId}
            onSelect={setSelectedId}
            palette={PSZ_SLATS_PALETTE}
          />
        )}
        {variant === 'cards' && (
          <CardGridView classes={ALL_CLASSES} selectedId={selectedId} onSelect={setSelectedId} />
        )}
        {variant === 'type-first' && (
          <TypeFirstView
            classes={ALL_CLASSES}
            selectedId={selectedId}
            onSelect={setSelectedId}
          />
        )}
      </div>
    </div>
  );
}
