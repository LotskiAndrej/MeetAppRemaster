'use strict';

const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function getUserName(uid) {
  const snap = await db.collection('users').doc(uid).get();
  const d = snap.data();
  return d ? `${d.firstName} ${d.lastName}` : 'Someone';
}

async function getCircleName(circleId) {
  const snap = await db.collection('circles').doc(circleId).get();
  return snap.data()?.name ?? 'Your Circle';
}

async function getTokensForUsers(userIds) {
  if (!userIds.length) return [];
  const snaps = await Promise.all(userIds.map(uid => db.collection('users').doc(uid).get()));
  return snaps.flatMap(snap => {
    const token = snap.data()?.fcmToken;
    return token ? [token] : [];
  });
}

async function sendNotification(tokens, title, body) {
  if (!tokens.length) return;
  try {
    await messaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  } catch (err) {
    console.error('sendNotification error:', err);
  }
}

// ---------------------------------------------------------------------------
// 1. New event created → notify all circle members (except organizer)
// ---------------------------------------------------------------------------

exports.onEventCreated = onDocumentCreated('events/{eventId}', async (event) => {
  const data = event.data.data();
  const { circleId, organizerId, place } = data;

  const [circleSnap, organizerName] = await Promise.all([
    db.collection('circles').doc(circleId).get(),
    getUserName(organizerId),
  ]);

  const circle = circleSnap.data();
  const circleName = circle?.name ?? 'Your Circle';
  const memberIds = (circle?.memberIds ?? []).filter(id => id !== organizerId);
  const tokens = await getTokensForUsers(memberIds);

  await sendNotification(
    tokens,
    `New event in ${circleName}`,
    `${organizerName} created a new event at ${place}`
  );
});

// ---------------------------------------------------------------------------
// 2. New comment → notify going users (except commenter)
// ---------------------------------------------------------------------------

exports.onCommentCreated = onDocumentCreated(
  'events/{eventId}/comments/{commentId}',
  async (event) => {
    const comment = event.data.data();
    const { eventId } = event.params;

    const eventSnap = await db.collection('events').doc(eventId).get();
    const eventData = eventSnap.data();
    if (!eventData) return;

    const participants = eventData.participants ?? {};
    const goingIds = Object.entries(participants)
      .filter(([uid, status]) => status === 'going' && uid !== comment.userId)
      .map(([uid]) => uid);

    const [circleName, commenterName, tokens] = await Promise.all([
      getCircleName(eventData.circleId),
      getUserName(comment.userId),
      getTokensForUsers(goingIds),
    ]);

    const truncated =
      comment.text.length > 80 ? comment.text.slice(0, 77) + '…' : comment.text;

    await sendNotification(
      tokens,
      `New comment on ${eventData.place} (${circleName})`,
      `${commenterName}: ${truncated}`
    );
  }
);

// ---------------------------------------------------------------------------
// 3. New proposal → notify going users (except proposer)
// ---------------------------------------------------------------------------

exports.onProposalCreated = onDocumentCreated(
  'events/{eventId}/proposals/{proposalId}',
  async (event) => {
    const proposal = event.data.data();
    const { eventId } = event.params;

    const eventSnap = await db.collection('events').doc(eventId).get();
    const eventData = eventSnap.data();
    if (!eventData) return;

    const participants = eventData.participants ?? {};
    const goingIds = Object.entries(participants)
      .filter(([uid, status]) => status === 'going' && uid !== proposal.proposerId)
      .map(([uid]) => uid);

    const parts = [];
    if (proposal.proposedPlace) parts.push(`place: ${proposal.proposedPlace}`);
    if (proposal.proposedDate) parts.push('new date');
    const changeDesc = parts.length ? parts.join(', ') : 'a change';

    const [circleName, proposerName, tokens] = await Promise.all([
      getCircleName(eventData.circleId),
      getUserName(proposal.proposerId),
      getTokensForUsers(goingIds),
    ]);

    await sendNotification(
      tokens,
      `New proposal for ${eventData.place} (${circleName})`,
      `${proposerName} proposed ${changeDesc}`
    );
  }
);

// ---------------------------------------------------------------------------
// 4. Proposal accepted / denied → notify all going users
// ---------------------------------------------------------------------------

exports.onProposalUpdated = onDocumentUpdated(
  'events/{eventId}/proposals/{proposalId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (before.status === after.status) return;
    if (after.status !== 'accepted' && after.status !== 'rejected') return;

    const { eventId } = event.params;
    const eventSnap = await db.collection('events').doc(eventId).get();
    const eventData = eventSnap.data();
    if (!eventData) return;

    const participants = eventData.participants ?? {};
    // Exclude the organizer — they made the decision, no need to notify themselves.
    const goingIds = Object.entries(participants)
      .filter(([uid, status]) => status === 'going' && uid !== eventData.organizerId)
      .map(([uid]) => uid);

    const action = after.status === 'accepted' ? 'accepted' : 'denied';
    const changeDesc = after.proposedPlace
      ? `New place: ${after.proposedPlace}`
      : 'Date change';

    const [circleName, tokens] = await Promise.all([
      getCircleName(eventData.circleId),
      getTokensForUsers(goingIds),
    ]);

    await sendNotification(
      tokens,
      `Proposal ${action} for ${eventData.place} (${circleName})`,
      changeDesc
    );
  }
);

// ---------------------------------------------------------------------------
// 5. User taps Going → notify the other users who are already going
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 6. Event deleted → notify going users (except organizer)
// ---------------------------------------------------------------------------

exports.onEventDeleted = onDocumentDeleted('events/{eventId}', async (event) => {
  const data = event.data.data();
  const { circleId, organizerId, place, participants } = data;

  const goingIds = Object.entries(participants ?? {})
    .filter(([uid, status]) => status === 'going' && uid !== organizerId)
    .map(([uid]) => uid);

  if (!goingIds.length) return;

  const [circleName, tokens] = await Promise.all([
    getCircleName(circleId),
    getTokensForUsers(goingIds),
  ]);

  await sendNotification(
    tokens,
    `Event cancelled in ${circleName}`,
    `The event at ${place} has been cancelled`
  );
});

// ---------------------------------------------------------------------------
// 5. User taps Going → notify the other users who are already going
// ---------------------------------------------------------------------------

exports.onEventUpdated = onDocumentUpdated('events/{eventId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  // --- Notify going users when place or date changes ---
  const placeChanged = before.place !== after.place;
  const dateChanged = before.date?.seconds !== after.date?.seconds;

  if (placeChanged || dateChanged) {
    const participants = after.participants ?? {};
    const goingIds = Object.entries(participants)
      .filter(([uid, status]) => status === 'going' && uid !== after.organizerId)
      .map(([uid]) => uid);

    if (goingIds.length) {
      const [circleName, tokens] = await Promise.all([
        getCircleName(after.circleId),
        getTokensForUsers(goingIds),
      ]);

      let body;
      if (placeChanged && dateChanged) {
        body = `Place changed to ${after.place} and date updated`;
      } else if (placeChanged) {
        body = `Place changed to ${after.place}`;
      } else {
        body = `Date/time updated for ${after.place}`;
      }

      await sendNotification(tokens, `Event updated in ${circleName}`, body);
    }
  }

  // --- Notify existing going users when someone new joins ---
  const beforeParticipants = before.participants ?? {};
  const afterParticipants = after.participants ?? {};

  const newlyGoingIds = Object.entries(afterParticipants)
    .filter(([uid, status]) => status === 'going' && beforeParticipants[uid] !== 'going')
    .map(([uid]) => uid);

  if (!newlyGoingIds.length) return;

  const existingGoingIds = Object.entries(afterParticipants)
    .filter(([uid, status]) => status === 'going' && !newlyGoingIds.includes(uid))
    .map(([uid]) => uid);

  if (!existingGoingIds.length) return;

  const [circleName, tokens] = await Promise.all([
    getCircleName(after.circleId),
    getTokensForUsers(existingGoingIds),
  ]);

  for (const uid of newlyGoingIds) {
    const name = await getUserName(uid);
    await sendNotification(
      tokens,
      `${name} is joining ${after.place} (${circleName})`,
      `${name} is also coming to ${after.place}`
    );
  }
});
