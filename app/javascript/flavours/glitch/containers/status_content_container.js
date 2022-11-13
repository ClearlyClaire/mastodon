import { connect } from 'react-redux';
import { injectIntl } from 'react-intl';
import StatusContent from 'flavours/glitch/components/status_content';
import { modifyStatusBody } from 'flavours/glitch/actions/statuses';
import spoilertextify from 'flavours/glitch/utils/spoilertextify';

const mapDispatchToProps = (dispatch, { intl, contextType }) => ({
  /**
   * Modifies the spoiler to be open or closed and then rewrites the
   * HTML of the status to reflect that state.
   *
   * This will also save any other changes to the HTML, for example
   * link rewriting.
   */
  onToggleSpoilerText (status, oldBody, spoilerElement, intl, open) {
    spoilerElement.replaceWith(spoilertextify(
      spoilerElement.getAttribute('data-spoilertext-content'),
      {
        emojos: status.get('emojis').reduce((obj, emoji) => {
          obj[`:${emoji.get('shortcode')}:`] = emoji.toJS();
          return obj;
        }, {}),
        intl,
        open: open == null
          ? !spoilerElement.classList.contains('open')
          : !!open,
      },
    ));
    dispatch(modifyStatusBody(
      status.get('id'),
      oldBody.innerHTML,
    ));
  },
});

export default injectIntl(connect(null, mapDispatchToProps)(StatusContent));