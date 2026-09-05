import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia_admin/core/auth/session_controller.dart';
import 'package:providentia_admin/features/access/access_repository.dart';
import 'package:providentia_admin/features/administrators/platform_administrators_page.dart';
import '../support/fake_api.dart';
import '../support/memory_credential_store.dart';

Future<SessionController> sessionFor(List<String> permissions) async {
 final store=MemoryCredentialStore(installationId:memoryInstallationId)..session=memoryStoredSession();
 final session=SessionController(api:FakeApi((_) async=>jsonResponse({
 'userId':store.session['userId'], 'profile':{'administratorAccess':{'features':{for(final p in permissions)p:true}}}})),credentialStore:store);
 await session.restore(); return session;
}
void main(){
 test('group listing is scoped and updates carry their revision',()async{
 final api=FakeApi((_)async=>jsonResponse({'data':[]}));final repository=AccessRepository(api);
 await repository.groups('home');
 expect(api.requests.single.query,{'scope':'home'});
 await repository.save({'id':'group-id','scope':'home','name':'Starter','description':'','features':{'members.invite':false},'limits':{'members.total':3},'delegablePermissions':[],'rolePermissions':{},'revision':7});
 expect(api.requests.last.method,'PUT'); expect((api.requests.last.body as Map)['expectedRevision'],7);
 });
 testWidgets('approval selects an unprotected group and submits both revisions',(tester)async{
 final session=await sessionFor(['administrators.read','administrators.approve']);addTearDown(session.dispose);
 final api=FakeApi((request)async{
 if(request.path.endsWith('/groups'))return jsonResponse({'data':[{'id':'root','name':'System owner','protected':true},{'id':'reviewers','name':'Reviewers','protected':false}]});
 return jsonResponse({'data':[{'user_id':'candidate','email':'candidate@example.test','status':'pending','revision':3,'groupAssignmentRevision':2}]});
 });
 await tester.pumpWidget(MaterialApp(home:Scaffold(body:PlatformAdministratorsPage(api:api,session:session))));await tester.pumpAndSettle();
 await tester.tap(find.text('Approve'));await tester.pumpAndSettle();
 expect(find.text('System owner'),findsNothing);await tester.tap(find.text('Reviewers'));await tester.pumpAndSettle();
 final review=api.requests.singleWhere((r)=>r.method=='POST');expect(review.path,'/api/v1/admin/administrators/candidate/review');
 expect(review.body,{'status':'approved','groupId':'reviewers','expectedRevision':3,'assignmentRevision':2});
 });
 testWidgets('listing permission cannot approve or change administrator groups',(tester)async{
 final session=await sessionFor(['administrators.read']);addTearDown(session.dispose);
 final api=FakeApi((_)async=>jsonResponse({'data':[{'user_id':'candidate','email':'candidate@example.test','status':'pending','revision':1}]}));
 await tester.pumpWidget(MaterialApp(home:Scaffold(body:PlatformAdministratorsPage(api:api,session:session))));await tester.pumpAndSettle();
 expect(find.text('Approve'),findsNothing);expect(find.text('Change group'),findsNothing);expect(api.requests.every((r)=>r.method=='GET'),isTrue);
 });
}
