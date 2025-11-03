const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

// Configurable constants
const RATE_LIMIT_SECONDS = 5 * 60; // 5 minutes
const GEOFENCE_METERS = 150; // allowable radius for location verification
const MAX_LOCATION_ACCURACY_METERS = 100; // require accuracy better than this to trust location

// Haversine distance (meters)
function haversineDistanceMeters(lat1, lon1, lat2, lon2) {
  function toRad(x) { return x * Math.PI / 180; }
  const R = 6371000; // Earth radius in meters
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
}

exports.validateSubmission = functions.region('us-central1').firestore
  .document('submissions/{submissionId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const docRef = snap.ref;
    const submissionId = context.params.submissionId;

    const hallID = data.hallID || null;
    const type = data.type || null; // expect 'waitTime' | 'seating' | 'rating'
    const uid = data.uid || null;
    const clientHash = data.clientIdentifierHash || null; // optional
    const createdAt = data.createdAt ? data.createdAt : admin.firestore.Timestamp.now();

    if (!hallID || !type) {
      await docRef.update({ serverValidated: false, serverValidationReason: 'missing_hall_or_type', serverValidatedAt: admin.firestore.Timestamp.now() });
      return null;
    }

    // Build a deterministic marker ID to rate-limit per user (or per clientHash when anonymous)
    let markerId = null;
    if (uid) markerId = `uid_${uid}_${hallID}_${type}`;
    else if (clientHash) markerId = `anon_${clientHash}_${hallID}_${type}`;

    const now = admin.firestore.Timestamp.now();

    try {
      await db.runTransaction(async (tx) => {
        // Rate limit check using a marker document
        if (markerId) {
          const markerRef = db.collection('submissionMarkers').doc(markerId);
          const markerSnap = await tx.get(markerRef);
          if (markerSnap.exists) {
            const last = markerSnap.get('last') || admin.firestore.Timestamp.fromMillis(0);
            const elapsed = now.seconds - last.seconds;
            if (elapsed < RATE_LIMIT_SECONDS) {
              // Block submission (mark as server-validated false)
              await tx.update(docRef, {
                serverValidated: false,
                serverValidationReason: 'rate_limited',
                serverValidatedAt: now
              });
              return;
            }
          }
          // Update marker to now
          tx.set(markerRef, { last: now }, { merge: true });
        }

        // Geofence verification
        let locationVerified = false;
        if (data.location && typeof data.location.lat === 'number' && typeof data.location.lon === 'number') {
          const lat = data.location.lat;
          const lon = data.location.lon;
          const accuracy = data.location.accuracyMeters || 999999;

          // Read hall coordinates from `halls` collection (assumption)
          const hallRef = db.collection('halls').doc(hallID);
          const hallSnap = await tx.get(hallRef);
          if (hallSnap.exists) {
            const hallLat = hallSnap.get('lat');
            const hallLon = hallSnap.get('lon');
            if (typeof hallLat === 'number' && typeof hallLon === 'number') {
              const dist = haversineDistanceMeters(lat, lon, hallLat, hallLon);
              if (dist <= GEOFENCE_METERS && accuracy <= MAX_LOCATION_ACCURACY_METERS) {
                locationVerified = true;
              }
            }
          }
        }

        // By default accept the submission (serverValidated: true) but attach locationVerified flag
        await tx.update(docRef, {
          serverValidated: true,
          serverValidationReason: null,
          serverValidatedAt: now,
          locationVerified: locationVerified
        });
      });
    } catch (err) {
      console.error('validateSubmission transaction failed:', err);
      // Best effort: mark as unchecked / error
      await docRef.update({ serverValidated: false, serverValidationReason: 'server_error', serverValidatedAt: admin.firestore.Timestamp.now() });
    }

    return null;
  });
