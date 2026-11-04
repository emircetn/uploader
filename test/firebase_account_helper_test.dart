import 'package:test/test.dart';
import 'package:uploader/src/helper/firebase_account_helper.dart';

void main() {
  test('reads every logged in account from login:list output', () {
    expect(
      FirebaseAccountHelper.parseLoginList(
        '{"status":"success","result":['
        '{"user":{"email":"a@x.com"},"tokens":{}},'
        '{"user":{"email":"b@x.com"},"tokens":{}}]}',
      ),
      ["a@x.com", "b@x.com"],
    );
  });

  test('no accounts, or output that is not JSON, reads as none', () {
    expect(
      FirebaseAccountHelper.parseLoginList('{"status":"success","result":[]}'),
      isEmpty,
    );
    expect(
      FirebaseAccountHelper.parseLoginList("No authorized accounts"),
      isEmpty,
    );
  });

  test('a FIREBASE_TOKEN is what the CLI uses first', () async {
    expect(
      await FirebaseAccountHelper().describe({"FIREBASE_TOKEN": "t"}),
      "FIREBASE_TOKEN environment variable",
    );
  });
}
