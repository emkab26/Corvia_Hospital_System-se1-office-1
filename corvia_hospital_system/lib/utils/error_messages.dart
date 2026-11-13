/// Turns an exception into something worth showing a patient.
///
/// The rule this exists to enforce: a raw exception never reaches the screen.
/// `Text('Could not save: $e')` puts Postgres and Supabase internals in front of
/// whoever is holding the phone - table names, row ids, JWT fragments - and it
/// tells them nothing they can act on.
///
/// Classification prefers the typed error and its code over reading the message.
/// Matching a bare '404' or '500' against `toString()` is how you decide a
/// request failed because a uuid happened to contain those digits, so codes come
/// from [PostgrestException.code] and [AuthException.statusCode], and the text
/// is only consulted for things that carry no code, such as a dead socket.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The reason a call failed, when it can be told, as a complete sentence.
///
/// Null when the error is not recognised: callers say what failed, and inventing
/// a cause for an unknown error is worse than admitting there isn't one.
String? friendlyErrorReason(Object error) {
  if (error is TimeoutException) return _timedOut;

  if (error is AuthException) {
    return _reasonForHttpStatus(error.statusCode) ?? _reasonFromText(error.message);
  }

  if (error is PostgrestException) {
    return _reasonForPostgresCode(error.code) ??
        _reasonForHttpStatus(error.code) ??
        _reasonFromText(error.message);
  }

  return _reasonFromText(error.toString());
}

/// A complete message for the user.
///
/// [whatFailed] is a sentence naming the action in the user's terms, such as
/// "Couldn't save the medical record." It is always included, so the message
/// still says what happened when the cause is unrecognised.
String friendlyErrorMessage(Object error, {required String whatFailed}) {
  final reason = friendlyErrorReason(error);
  return reason == null ? '$whatFailed Please try again.' : '$whatFailed $reason';
}

const String _timedOut = 'The server took too long to respond. Please try again.';
const String _offline = 'Check your connection and try again.';
const String _sessionExpired =
    'Your session has expired. Please sign in and try again.';
const String _noPermission = 'You do not have permission to do that.';
const String _notFound = 'We could not find what you were looking for.';
const String _conflict = 'Check your details and try again.';
const String _rateLimited = 'Too many attempts. Please wait a moment and try again.';
const String _serverProblem = 'The server had a problem. Please try again shortly.';

String? _reasonForHttpStatus(String? status) {
  switch (status) {
    case '401':
      return _sessionExpired;
    case '403':
      return _noPermission;
    case '404':
      return _notFound;
    case '409':
      return _conflict;
    case '429':
      return _rateLimited;
    case '500':
    case '502':
    case '503':
    case '504':
      return _serverProblem;
    default:
      return null;
  }
}

String? _reasonForPostgresCode(String? code) {
  switch (code) {
    case '23505': // unique_violation
    case '23503': // foreign_key_violation
    case '23P01': // exclusion_violation
      return _conflict;
    case '42501': // insufficient_privilege, which is what RLS denials arrive as
      return _noPermission;
    case 'PGRST116': // no rows where exactly one was expected
      return _notFound;
    default:
      return null;
  }
}

/// Last resort, for errors that carry no code. Only phrases specific enough to
/// mean one thing - deliberately no bare status numbers, which match anything.
String? _reasonFromText(String text) {
  final raw = text.toLowerCase();

  if (_has(raw, const [
    'socketexception',
    'failed host lookup',
    'network is unreachable',
    'connection refused',
    'connection closed',
    'connection reset',
    'no address associated',
    'clientexception',
  ])) {
    return _offline;
  }
  if (_has(raw, const ['timeout', 'timed out'])) return _timedOut;
  if (_has(raw, const [
    'row-level security',
    'violates row-level',
    'permission denied',
    'forbidden',
  ])) {
    return _noPermission;
  }
  if (_has(raw, const ['jwt expired', 'invalid token', 'unauthorized'])) {
    return _sessionExpired;
  }
  if (_has(raw, const ['rate limit', 'too many requests'])) return _rateLimited;
  if (_has(raw, const [
    'internal server error',
    'bad gateway',
    'service unavailable',
  ])) {
    return _serverProblem;
  }
  if (_has(raw, const ['duplicate key', 'already exists', 'unique constraint'])) {
    return _conflict;
  }

  return null;
}

bool _has(String haystack, List<String> needles) =>
    needles.any(haystack.contains);
