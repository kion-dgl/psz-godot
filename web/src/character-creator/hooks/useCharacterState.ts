import { useReducer } from 'react';

export type Step = 'class' | 'appearance' | 'name' | 'confirm';

const STEP_ORDER: Step[] = ['class', 'appearance', 'name', 'confirm'];

export interface CharacterState {
  step: Step;
  classId: string | null;
  variationIndex: number;
  hairColorIndex: number;
  skinToneIndex: number;
  bodyColorIndex: number;
  name: string;
}

export type CharacterAction =
  | { type: 'SET_CLASS'; classId: string }
  | { type: 'SET_VARIATION'; index: number }
  | { type: 'SET_HAIR_COLOR'; index: number }
  | { type: 'SET_SKIN_TONE'; index: number }
  | { type: 'SET_BODY_COLOR'; index: number }
  | { type: 'SET_NAME'; name: string }
  | { type: 'NEXT_STEP' }
  | { type: 'PREV_STEP' }
  | { type: 'GO_TO_STEP'; step: Step }
  | { type: 'RESET' };

const initialState: CharacterState = {
  step: 'class',
  classId: null,
  variationIndex: 0,
  hairColorIndex: 0,
  skinToneIndex: 0,
  bodyColorIndex: 0,
  name: '',
};

function reducer(state: CharacterState, action: CharacterAction): CharacterState {
  switch (action.type) {
    case 'SET_CLASS':
      return { ...state, classId: action.classId, variationIndex: 0, hairColorIndex: 0, skinToneIndex: 0, bodyColorIndex: 0 };
    case 'SET_VARIATION':
      return { ...state, variationIndex: action.index };
    case 'SET_HAIR_COLOR':
      return { ...state, hairColorIndex: action.index };
    case 'SET_SKIN_TONE':
      return { ...state, skinToneIndex: action.index };
    case 'SET_BODY_COLOR':
      return { ...state, bodyColorIndex: action.index };
    case 'SET_NAME':
      return { ...state, name: action.name };
    case 'NEXT_STEP': {
      const idx = STEP_ORDER.indexOf(state.step);
      if (idx < STEP_ORDER.length - 1) {
        return { ...state, step: STEP_ORDER[idx + 1] };
      }
      return state;
    }
    case 'PREV_STEP': {
      const idx = STEP_ORDER.indexOf(state.step);
      if (idx > 0) {
        return { ...state, step: STEP_ORDER[idx - 1] };
      }
      return state;
    }
    case 'GO_TO_STEP':
      return { ...state, step: action.step };
    case 'RESET':
      return { ...initialState };
    default:
      return state;
  }
}

export function useCharacterState() {
  const [state, dispatch] = useReducer(reducer, initialState);

  const stepIndex = STEP_ORDER.indexOf(state.step);

  const canGoNext = (): boolean => {
    switch (state.step) {
      case 'class': return state.classId !== null;
      case 'appearance': return true;
      case 'name': return state.name.trim().length > 0;
      case 'confirm': return false;
      default: return false;
    }
  };

  const canGoBack = stepIndex > 0;

  return { state, dispatch, stepIndex, stepCount: STEP_ORDER.length, canGoNext: canGoNext(), canGoBack };
}
