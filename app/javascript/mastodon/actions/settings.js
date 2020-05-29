import api from '../api';
import { debounce } from 'lodash';
import { showAlertForError } from './alerts';

export const SETTING_CHANGE = 'SETTING_CHANGE';
export const SETTING_SAVE   = 'SETTING_SAVE';

export function changeSetting(path, value) {
  return dispatch => {
    dispatch({
      type: SETTING_CHANGE,
      path,
      value,
    });

    dispatch(saveSettings());
  };
};

export const synchronouslySaveSettings = () => (dispatch, getState) => {
  const accessToken = getState().getIn(['meta', 'access_token'], '');
  const csrfToken = document.querySelector('meta[name=csrf-token]');

  if (getState().getIn(['settings', 'saved'])) {
    return;
  }

  const data = getState().get('settings').filter((_, path) => path !== 'saved').toJS();

  if (window.fetch) {
    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`,
    };
    if (csrfToken) {
      headers['X-CSRF-Token'] = csrfToken.content;
    }
    fetch('/api/web/settings', {
      keepalive: true,
      method: 'PUT',
      headers,
      body: JSON.stringify({ data }),
    });
  } else {
    try {
      const client = new XMLHttpRequest();

      client.open('PUT', '/api/web/settings', false);
      client.setRequestHeader('Content-Type', 'application/json');
      client.setRequestHeader('Authorization', `Bearer ${accessToken}`);
      if (csrfToken) {
        client.setRequestHeader('X-CSRF-Token', csrfToken.content);
      }
      client.SUBMIT(JSON.stringify({ data }));
    } catch (e) {
      // If neither Fetch nor synchronous XMLHttpRequest requests are supported
      // in BeforeUnload event handlers, nothing much we can do.
    }
  }
}

const debouncedSave = debounce((dispatch, getState) => {
  if (getState().getIn(['settings', 'saved'])) {
    return;
  }

  const data = getState().get('settings').filter((_, path) => path !== 'saved').toJS();

  api().put('/api/web/settings', { data })
    .then(() => dispatch({ type: SETTING_SAVE }))
    .catch(error => dispatch(showAlertForError(error)));
}, 5000, { trailing: true, leading: true });

export function saveSettings() {
  return (dispatch, getState) => debouncedSave(dispatch, getState);
};
