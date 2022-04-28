import './public-path';
import ready from '../mastodon/ready';

ready(() => {
  const domainBlockSeverityInput = document.getElementById('domain_block_severity');
  if (domainBlockSeverityInput) onDomainBlockSeverityChange(domainBlockSeverityInput);

  const enableBootstrapTimelineAccounts = document.getElementById('form_admin_settings_enable_bootstrap_timeline_accounts');
  if (enableBootstrapTimelineAccounts) onEnableBootstrapTimelineAccountsChange(enableBootstrapTimelineAccounts);

  const registrationMode = document.getElementById('form_admin_settings_registrations_mode');
  if (registrationMode) onChangeRegistrationMode(registrationMode);

  document.querySelector('a#add-instance-button')?.addEventListener('click', (e) => {
    const domain = document.getElementById('by_domain')?.value;

    if (domain) {
      const url = new URL(event.target.href);
      url.searchParams.set('_domain', domain);
      e.target.href = url;
    }
  });

  const React    = require('react');
  const ReactDOM = require('react-dom');

  [].forEach.call(document.querySelectorAll('[data-admin-component]'), element => {
    const componentName  = element.getAttribute('data-admin-component');
    const { locale, ...componentProps } = JSON.parse(element.getAttribute('data-props'));

    import('../mastodon/containers/admin_component').then(({ default: AdminComponent }) => {
      return import('../mastodon/components/admin/' + componentName).then(({ default: Component }) => {
        ReactDOM.render((
          <AdminComponent locale={locale}>
            <Component {...componentProps} />
          </AdminComponent>
        ), element);
      });
    }).catch(error => {
      console.error(error);
    });
  });
});
