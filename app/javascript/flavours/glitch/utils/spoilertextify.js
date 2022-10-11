import { defineMessages } from 'react-intl';
import emojify from 'flavours/glitch/features/emoji/emoji';

const messages = defineMessages({
  spoilerHidden: {
    id: 'status.spoilertext.hidden',
    defaultMessage: '[currently hidden]',
  },
  showSpoiler: {
    id: `status.spoilertext.show`,
    defaultMessage: `show spoiler`,
  },
});

/**
 * Generates a `<span>` node which represents an inline spoiler for the
 * provided text.
 */
export default (text, options) => {
  const doc = options?.document || document;
  const emojiMap = options?.emojos || {};
  const { intl, open } = options;
  const result = doc.createElement('span');
  result.className = open ? 'spoilertext open' : 'spoilertext';
  result.setAttribute('data-spoilertext-content', text);
  if (!open) {
    const accessibleDescription = doc.createElement('span');
    accessibleDescription.className = 'spoilertext--screenreader-only';
    accessibleDescription.textContent = intl?.formatMessage?.(messages.spoilerHidden) || '';
    result.append(accessibleDescription);
  }
  const textElt = doc.createElement('span');
  textElt.className = 'spoilertext--content';
  textElt.setAttribute('aria-hidden', open ? 'false' : 'true');
  textElt.textContent = text;
  textElt.innerHTML = emojify(textElt.innerHTML, emojiMap);
  const togglerSpan = doc.createElement('span');
  togglerSpan.className = 'spoilertext--span';
  const togglerButton = doc.createElement('button');
  togglerButton.className = 'spoilertext--button';
  const togglerMessage = intl?.formatMessage?.(messages.showSpoiler) || '';
  togglerButton.setAttribute('type', 'button');
  togglerButton.setAttribute('aria-label', togglerMessage);
  togglerButton.setAttribute('aria-pressed', open ? 'true' : 'false');
  togglerButton.setAttribute('title', togglerMessage);
  const togglerIcon = doc.createElement('i');
  togglerIcon.setAttribute('role', 'img');
  togglerIcon.setAttribute(
    'class',
    `fa ${open ? 'fa-eye-slash' : 'fa-eye'}`,
  );
  togglerButton.append(togglerIcon);
  togglerSpan.append(
    '\u2060', // word joiner to prevent a linebreak
    togglerButton,
  );
  result.append(textElt, togglerSpan);
  return result;
};
