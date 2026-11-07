import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/pms/pm_logic.dart';

void main() {
  test('unverified claims cannot bypass friend or block policies', () {
    expect(
      PmLogic.senderAllowed(
        verified: false,
        scope: 'friends',
        isFriend: true,
        hasBlockedUsers: false,
      ),
      isFalse,
    );
    expect(
      PmLogic.senderAllowed(
        verified: false,
        scope: 'everyone',
        isFriend: false,
        hasBlockedUsers: true,
      ),
      isFalse,
    );
    expect(
      PmLogic.senderAllowed(
        verified: false,
        scope: 'everyone',
        isFriend: false,
        hasBlockedUsers: false,
      ),
      isTrue,
    );
    expect(
      PmLogic.senderAllowed(
        verified: true,
        scope: 'friends',
        isFriend: true,
        hasBlockedUsers: true,
      ),
      isTrue,
    );
    expect(
      PmLogic.senderAllowed(
        verified: true,
        scope: 'disabled',
        isFriend: true,
        hasBlockedUsers: false,
      ),
      isFalse,
    );
  });
}
