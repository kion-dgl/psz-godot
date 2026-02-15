/**
 * useStageConfigs — Loads stage configs and provides gate helpers
 *
 * Loads all *_configs.json from /data/stage_configs/ at startup.
 * Provides filtering by area/variant and rotation-aware gate matching.
 */

import { useState, useEffect, useMemo } from 'react';
import type { StageConfig, Direction } from '../types';
import { EDITOR_AREAS } from '../types';

// Module-level config cache (shared across all hook instances)
let _configCache: Record<string, StageConfig> | null = null;
let _configPromise: Promise<Record<string, StageConfig>> | null = null;

const CONFIG_FILES = [
  'paru_configs',
  'valley_configs',
  'wetlands_configs',
  'snowfield_configs',
];

async function loadAllConfigs(): Promise<Record<string, StageConfig>> {
  if (_configCache) return _configCache;
  if (_configPromise) return _configPromise;

  _configPromise = (async () => {
    const merged: Record<string, StageConfig> = {};
    const base = import.meta.env.BASE_URL || '/';
    await Promise.all(
      CONFIG_FILES.map(async (name) => {
        try {
          const resp = await fetch(`${base}data/stage_configs/${name}.json`);
          if (resp.ok) {
            const data = await resp.json();
            Object.assign(merged, data);
          }
        } catch {
          // Config file not available, skip
        }
      })
    );
    _configCache = merged;
    return merged;
  })();

  return _configPromise;
}

// ============================================================================
// Gate helpers
// ============================================================================

const DIRECTION_ORDER: Direction[] = ['north', 'east', 'south', 'west'];

/** Get original gate directions for a stage (before rotation) */
export function getOriginalGates(stageName: string): Set<Direction> {
  if (!_configCache) return new Set();
  const config = _configCache[stageName];
  if (!config) return new Set();
  return new Set(config.gates.map(g => g.edge as Direction));
}

/** Rotate a direction CW by degrees (0, 90, 180, 270) */
export function rotateDirection(dir: Direction, rotation: number): Direction {
  if (rotation === 0) return dir;
  const idx = DIRECTION_ORDER.indexOf(dir);
  if (idx < 0) return dir;
  const steps = ((rotation / 90) % 4 + 4) % 4;
  return DIRECTION_ORDER[(idx + steps) % 4];
}

/** Get gate directions after applying rotation (grid-space gates) */
export function getRotatedGates(stageName: string, rotation: number): Set<Direction> {
  const original = getOriginalGates(stageName);
  if (rotation === 0) return original;
  return new Set([...original].map(g => rotateDirection(g, rotation)));
}

/** Get opposite direction */
export function oppositeDirection(dir: Direction): Direction {
  const opposites: Record<Direction, Direction> = {
    north: 'south',
    south: 'north',
    east: 'west',
    west: 'east',
  };
  return opposites[dir];
}

/** Get neighbor position in a direction */
export function getNeighbor(row: number, col: number, dir: Direction): [number, number] {
  switch (dir) {
    case 'north': return [row - 1, col];
    case 'south': return [row + 1, col];
    case 'east': return [row, col + 1];
    case 'west': return [row, col - 1];
  }
}

/** Check if position is valid in grid */
export function isValidPos(row: number, col: number, gridSize: number): boolean {
  return row >= 0 && row < gridSize && col >= 0 && col < gridSize;
}

/** Get the StageConfig for a stage name */
export function getStageConfig(stageName: string): StageConfig | undefined {
  if (!_configCache) return undefined;
  return _configCache[stageName];
}

// ============================================================================
// Stage filtering
// ============================================================================

/** Get all stage names for an area and variant */
export function getStagesForArea(areaKey: string, variant: string): string[] {
  if (!_configCache) return [];
  const area = EDITOR_AREAS.find(a => a.key === areaKey);
  if (!area) return [];
  const prefix = `${area.prefix}${variant}_`;
  return Object.keys(_configCache).filter(k => k.startsWith(prefix));
}

/** Get stage suffix (e.g., "ib1" from "s01a_ib1") */
export function getStageSuffix(stageName: string): string {
  const idx = stageName.indexOf('_');
  return idx >= 0 ? stageName.substring(idx + 1) : stageName;
}

// ============================================================================
// Hook
// ============================================================================

export interface UseStageConfigsReturn {
  allConfigs: Record<string, StageConfig>;
  getStages: (areaKey: string, variant: string) => string[];
  getConfig: (stageName: string) => StageConfig | undefined;
  isLoading: boolean;
}

export function useStageConfigs(): UseStageConfigsReturn {
  const [allConfigs, setAllConfigs] = useState<Record<string, StageConfig>>(_configCache || {});
  const [isLoading, setIsLoading] = useState(!_configCache);

  useEffect(() => {
    if (_configCache) {
      setAllConfigs(_configCache);
      setIsLoading(false);
      return;
    }
    loadAllConfigs().then((configs) => {
      setAllConfigs(configs);
      setIsLoading(false);
    });
  }, []);

  const getStages = useMemo(() => {
    const cache = new Map<string, string[]>();
    return (areaKey: string, variant: string): string[] => {
      const key = `${areaKey}:${variant}`;
      if (!cache.has(key)) {
        cache.set(key, getStagesForArea(areaKey, variant));
      }
      return cache.get(key)!;
    };
  }, [allConfigs]);

  return {
    allConfigs,
    getStages,
    getConfig: getStageConfig,
    isLoading,
  };
}
