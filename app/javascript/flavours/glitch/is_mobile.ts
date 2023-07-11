import { supportsPassiveEvents } from 'detect-passive-events';

import { forceSingleColumn, hasMultiColumnPath } from './initial_state';

const LAYOUT_BREAKPOINT = 630;

export const isMobile = (width: number) => width <= LAYOUT_BREAKPOINT;

export const transientSingleColumn = !forceSingleColumn && !hasMultiColumnPath;

export type LayoutType = 'mobile' | 'single-column' | 'multi-column';
export const layoutFromWindow = (layout_local_setting: string): LayoutType => {
  switch (layout_local_setting) {
    case 'multiple':
      return 'multi-column';
    case 'single':
      if (isMobile(window.innerWidth)) {
        return 'mobile';
      } else {
        return 'single-column';
      }
    default:
      if (isMobile(window.innerWidth)) {
        return 'mobile';
      } else if (!forceSingleColumn && !transientSingleColumn) {
        return 'multi-column';
      } else {
        return 'single-column';
      }
  }
};

const listenerOptions = supportsPassiveEvents ? { passive: true } : false;

let userTouching = false;

const touchListener = () => {
  userTouching = true;

  window.removeEventListener('touchstart', touchListener);
};

window.addEventListener('touchstart', touchListener, listenerOptions);

export const isUserTouching = () => userTouching;
