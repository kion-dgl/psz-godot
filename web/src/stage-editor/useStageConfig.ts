import { useState, useEffect, useCallback } from 'react';
import { assetUrl } from '../utils/assets';
import type { UnifiedStageConfig } from './types';
import { createDefaultConfig } from './types';

const STORAGE_KEY = 'unified-stage-configs';
const TEXTURE_FIXES_KEY = 'global-texture-fixes';
const SEEDED_KEY = 'stage-configs-seeded';
const MAX_UNDO_STACK = 50;

// =============== One-time seeding from committed JSON ===============
// On first visit (no localStorage data), fetch committed configs and
// texture fixes and write them into localStorage. After that the app
// works entirely off localStorage — no async merge on every load.

let _seedPromise: Promise<void> | null = null;

export function ensureSeeded(): Promise<void> {
  if (_seedPromise) return _seedPromise;

  // Already seeded in a previous session
  if (localStorage.getItem(SEEDED_KEY)) {
    _seedPromise = Promise.resolve();
    return _seedPromise;
  }

  _seedPromise = (async () => {
    try {
      // Seed stage configs if localStorage is empty
      const existingConfigs = localStorage.getItem(STORAGE_KEY);
      if (!existingConfigs) {
        const resp = await fetch(assetUrl('data/stage_configs/unified-stage-configs.json'));
        if (resp.ok) {
          const committed = await resp.json();
          localStorage.setItem(STORAGE_KEY, JSON.stringify(committed));
        }
      }

      // Seed texture fixes if localStorage is empty
      const existingFixes = localStorage.getItem(TEXTURE_FIXES_KEY);
      if (!existingFixes) {
        const resp = await fetch(assetUrl('data/stage_configs/global-texture-fixes.json'));
        if (resp.ok) {
          const committed = await resp.json();
          localStorage.setItem(TEXTURE_FIXES_KEY, JSON.stringify(committed));
        }
      }

      localStorage.setItem(SEEDED_KEY, new Date().toISOString());
    } catch (e) {
      console.warn('Failed to seed stage configs from committed data:', e);
    }
  })();

  return _seedPromise;
}

// =============== Type exports ===============

export type GlobalTextureFix = {
  repeatX: number;
  repeatY: number;
  offsetX: number;
  offsetY: number;
  scrollX?: number;
  scrollY?: number;
  wrapS?: 'repeat' | 'mirror' | 'clamp';
  wrapT?: 'repeat' | 'mirror' | 'clamp';
};

// =============== localStorage helpers ===============

function loadAllConfigs(): Record<string, UnifiedStageConfig> {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored ? JSON.parse(stored) : {};
  } catch {
    return {};
  }
}

function saveAllConfigs(configs: Record<string, UnifiedStageConfig>) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(configs));
  } catch (e) {
    console.error('Failed to save stage configs:', e);
  }
}

// Deep clone config for undo stack
function cloneConfig(config: UnifiedStageConfig): UnifiedStageConfig {
  return JSON.parse(JSON.stringify(config));
}

// =============== Hook ===============

export interface UseStageConfigReturn {
  config: UnifiedStageConfig | null;
  updateConfig: (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => void;
  setConfig: (config: UnifiedStageConfig) => void;
  undo: () => void;
  redo: () => void;
  canUndo: boolean;
  canRedo: boolean;
  saveNow: () => void;
  resetToDefault: () => void;
}

export function useStageConfig(mapId: string): UseStageConfigReturn {
  const [config, setConfigState] = useState<UnifiedStageConfig | null>(null);
  const [undoStack, setUndoStack] = useState<UnifiedStageConfig[]>([]);
  const [redoStack, setRedoStack] = useState<UnifiedStageConfig[]>([]);
  const [isDirty, setIsDirty] = useState(false);

  // Load config on mount or mapId change — wait for seed, then read localStorage
  useEffect(() => {
    let cancelled = false;
    ensureSeeded().then(() => {
      if (cancelled) return;
      const configs = loadAllConfigs();
      const loaded = configs[mapId] || createDefaultConfig(mapId);
      setConfigState(loaded);
      setUndoStack([]);
      setRedoStack([]);
      setIsDirty(false);
    });
    return () => { cancelled = true; };
  }, [mapId]);

  // Auto-save when dirty (debounced)
  useEffect(() => {
    if (!config || !isDirty) return;

    const timeout = setTimeout(() => {
      const configs = loadAllConfigs();
      configs[mapId] = { ...config, lastModified: new Date().toISOString() };
      saveAllConfigs(configs);
      setIsDirty(false);
    }, 500);

    return () => clearTimeout(timeout);
  }, [config, mapId, isDirty]);

  // Update config with undo support
  const updateConfig = useCallback(
    (updater: (prev: UnifiedStageConfig) => UnifiedStageConfig) => {
      setConfigState((prev) => {
        if (!prev) return prev;

        setUndoStack((stack) => {
          const newStack = [...stack, cloneConfig(prev)];
          if (newStack.length > MAX_UNDO_STACK) {
            return newStack.slice(-MAX_UNDO_STACK);
          }
          return newStack;
        });

        setRedoStack([]);
        setIsDirty(true);

        return updater(prev);
      });
    },
    []
  );

  // Direct set (also pushes to undo)
  const setConfig = useCallback((newConfig: UnifiedStageConfig) => {
    setConfigState((prev) => {
      if (prev) {
        setUndoStack((stack) => {
          const newStack = [...stack, cloneConfig(prev)];
          if (newStack.length > MAX_UNDO_STACK) {
            return newStack.slice(-MAX_UNDO_STACK);
          }
          return newStack;
        });
        setRedoStack([]);
      }
      setIsDirty(true);
      return newConfig;
    });
  }, []);

  // Undo
  const undo = useCallback(() => {
    if (undoStack.length === 0) return;

    const prev = undoStack[undoStack.length - 1];
    setUndoStack((stack) => stack.slice(0, -1));

    setConfigState((current) => {
      if (current) {
        setRedoStack((stack) => [...stack, cloneConfig(current)]);
      }
      setIsDirty(true);
      return prev;
    });
  }, [undoStack]);

  // Redo
  const redo = useCallback(() => {
    if (redoStack.length === 0) return;

    const next = redoStack[redoStack.length - 1];
    setRedoStack((stack) => stack.slice(0, -1));

    setConfigState((current) => {
      if (current) {
        setUndoStack((stack) => [...stack, cloneConfig(current)]);
      }
      setIsDirty(true);
      return next;
    });
  }, [redoStack]);

  // Force save now
  const saveNow = useCallback(() => {
    if (!config) return;
    const configs = loadAllConfigs();
    configs[mapId] = { ...config, lastModified: new Date().toISOString() };
    saveAllConfigs(configs);
    setIsDirty(false);
  }, [config, mapId]);

  // Reset to default
  const resetToDefault = useCallback(() => {
    const defaultConfig = createDefaultConfig(mapId);
    setConfig(defaultConfig);
  }, [mapId, setConfig]);

  return {
    config,
    updateConfig,
    setConfig,
    undo,
    redo,
    canUndo: undoStack.length > 0,
    canRedo: redoStack.length > 0,
    saveNow,
    resetToDefault,
  };
}

// Helper to get all saved map IDs
export function getSavedMapIds(): string[] {
  const configs = loadAllConfigs();
  return Object.keys(configs);
}

// Helper to export config as JSON
export function exportConfigAsJson(config: UnifiedStageConfig): string {
  return JSON.stringify(config, null, 2);
}

// Helper to import config from JSON
export function importConfigFromJson(json: string): UnifiedStageConfig | null {
  try {
    const parsed = JSON.parse(json);
    if (parsed.mapId && parsed.version) {
      return parsed as UnifiedStageConfig;
    }
    return null;
  } catch {
    return null;
  }
}

// Re-export loadAllConfigs for ExportTab bulk export
export { loadAllConfigs };
