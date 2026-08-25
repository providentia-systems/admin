const requestId = '11111111-1111-4111-8111-111111111111';
const approvalToken =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Uri validAdminLink() => Uri.parse(
  'providentia-admin://login-link/admin#requestId=$requestId&approval=$approvalToken',
);
