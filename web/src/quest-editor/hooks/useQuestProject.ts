/**
 * useQuestProject — localStorage persistence with undo/redo
 */

import { useState, useEffect, useCallback } from 'react';
import type { QuestProject } from '../types';
import { createDefaultProject } from '../types';

const STORAGE_KEY = 'quest-editor-projects';
const MAX_UNDO_STACK = 50;

function loadAllProjects(): Record<string, QuestProject> {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored ? JSON.parse(stored) : {};
  } catch {
    return {};
  }
}

function saveAllProjects(projects: Record<string, QuestProject>) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(projects));
  } catch (e) {
    console.error('Failed to save quest projects:', e);
  }
}

function cloneProject(project: QuestProject): QuestProject {
  return JSON.parse(JSON.stringify(project));
}

export interface UseQuestProjectReturn {
  project: QuestProject;
  updateProject: (updater: (prev: QuestProject) => QuestProject) => void;
  setProject: (project: QuestProject) => void;
  undo: () => void;
  redo: () => void;
  canUndo: boolean;
  canRedo: boolean;
  saveNow: () => void;
  loadProject: (id: string) => void;
  deleteProject: (id: string) => void;
  newProject: () => void;
  savedProjectIds: string[];
  getSavedProject: (id: string) => QuestProject | null;
}

export function useQuestProject(): UseQuestProjectReturn {
  const [project, setProjectState] = useState<QuestProject>(() => {
    const projects = loadAllProjects();
    const lastId = localStorage.getItem('quest-editor-active');
    if (lastId && projects[lastId]) return projects[lastId];
    const ids = Object.keys(projects);
    if (ids.length > 0) return projects[ids[0]];
    return createDefaultProject();
  });
  const [undoStack, setUndoStack] = useState<QuestProject[]>([]);
  const [redoStack, setRedoStack] = useState<QuestProject[]>([]);
  const [isDirty, setIsDirty] = useState(false);
  const [savedIds, setSavedIds] = useState<string[]>(() => Object.keys(loadAllProjects()));

  useEffect(() => {
    localStorage.setItem('quest-editor-active', project.id);
  }, [project.id]);

  useEffect(() => {
    if (!isDirty) return;
    const timeout = setTimeout(() => {
      const projects = loadAllProjects();
      projects[project.id] = { ...project, lastModified: new Date().toISOString() };
      saveAllProjects(projects);
      setSavedIds(Object.keys(projects));
      setIsDirty(false);
    }, 500);
    return () => clearTimeout(timeout);
  }, [project, isDirty]);

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey) {
        e.preventDefault();
        undo();
      }
      if ((e.ctrlKey || e.metaKey) && (e.key === 'y' || (e.key === 'z' && e.shiftKey))) {
        e.preventDefault();
        redo();
      }
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [undoStack, redoStack]);

  const updateProject = useCallback(
    (updater: (prev: QuestProject) => QuestProject) => {
      setProjectState((prev) => {
        setUndoStack((stack) => {
          const newStack = [...stack, cloneProject(prev)];
          return newStack.length > MAX_UNDO_STACK ? newStack.slice(-MAX_UNDO_STACK) : newStack;
        });
        setRedoStack([]);
        setIsDirty(true);
        return updater(prev);
      });
    },
    []
  );

  const setProject = useCallback((newProject: QuestProject) => {
    setProjectState((prev) => {
      setUndoStack((stack) => {
        const newStack = [...stack, cloneProject(prev)];
        return newStack.length > MAX_UNDO_STACK ? newStack.slice(-MAX_UNDO_STACK) : newStack;
      });
      setRedoStack([]);
      setIsDirty(true);
      return newProject;
    });
  }, []);

  const undo = useCallback(() => {
    if (undoStack.length === 0) return;
    const prev = undoStack[undoStack.length - 1];
    setUndoStack((stack) => stack.slice(0, -1));
    setProjectState((current) => {
      setRedoStack((stack) => [...stack, cloneProject(current)]);
      setIsDirty(true);
      return prev;
    });
  }, [undoStack]);

  const redo = useCallback(() => {
    if (redoStack.length === 0) return;
    const next = redoStack[redoStack.length - 1];
    setRedoStack((stack) => stack.slice(0, -1));
    setProjectState((current) => {
      setUndoStack((stack) => [...stack, cloneProject(current)]);
      setIsDirty(true);
      return next;
    });
  }, [redoStack]);

  const saveNow = useCallback(() => {
    const projects = loadAllProjects();
    projects[project.id] = { ...project, lastModified: new Date().toISOString() };
    saveAllProjects(projects);
    setSavedIds(Object.keys(projects));
    setIsDirty(false);
  }, [project]);

  const loadProject = useCallback((id: string) => {
    const projects = loadAllProjects();
    if (projects[id]) {
      setProjectState(projects[id]);
      setUndoStack([]);
      setRedoStack([]);
      setIsDirty(false);
    }
  }, []);

  const deleteProject = useCallback((id: string) => {
    const projects = loadAllProjects();
    delete projects[id];
    saveAllProjects(projects);
    setSavedIds(Object.keys(projects));
    if (id === project.id) {
      const remaining = Object.keys(projects);
      if (remaining.length > 0) {
        setProjectState(projects[remaining[0]]);
      } else {
        setProjectState(createDefaultProject());
      }
      setUndoStack([]);
      setRedoStack([]);
      setIsDirty(false);
    }
  }, [project.id]);

  const newProject = useCallback(() => {
    const projects = loadAllProjects();
    projects[project.id] = { ...project, lastModified: new Date().toISOString() };
    saveAllProjects(projects);
    const fresh = createDefaultProject();
    setProjectState(fresh);
    setUndoStack([]);
    setRedoStack([]);
    setIsDirty(true);
    setSavedIds(Object.keys(projects));
  }, [project]);

  const getSavedProject = useCallback((id: string): QuestProject | null => {
    const projects = loadAllProjects();
    return projects[id] || null;
  }, []);

  return {
    project,
    updateProject,
    setProject,
    undo,
    redo,
    canUndo: undoStack.length > 0,
    canRedo: redoStack.length > 0,
    saveNow,
    loadProject,
    deleteProject,
    newProject,
    savedProjectIds: savedIds,
    getSavedProject,
  };
}
