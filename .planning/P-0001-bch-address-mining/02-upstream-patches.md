# Upstream patches to port — saved from bitbucket.org/ckolivas/ckpool (shallow clone)

## Commit a439cf9
```diff
commit a439cf96aad4f9a906f601675f8a12444e0f4d21
Author: Jaroslav (Jerry) Langer <jaroslav.langer@braiins.cz>
Date:   Fri Dec 19 17:10:27 2025 +0100

    Fix workbase_id double increment.

diff --git a/src/stratifier.c b/src/stratifier.c
index 94a91e3..20e4b16 100644
--- a/src/stratifier.c
+++ b/src/stratifier.c
@@ -5624,7 +5624,7 @@ static void add_submit(ckpool_t *ckp, stratum_instance_t *client, const double d
 	tv_time(&now_t);
 
 	ck_rlock(&sdata->workbase_lock);
-	next_blockid = sdata->workbase_id + 1;
+	next_blockid = sdata->workbase_id;
 	if (ckp->proxy)
 		network_diff = sdata->current_workbase->diff;
 	else
@@ -6489,7 +6489,7 @@ static void suggest_diff(ckpool_t *ckp, stratum_instance_t *client, const char *
 	client->suggest_diff = sdiff;
 	if (client->diff == sdiff)
 		return;
-	client->diff_change_job_id = client->sdata->workbase_id + 1;
+	client->diff_change_job_id = client->sdata->workbase_id;
 	client->old_diff = client->diff;
 	client->diff = sdiff;
 	stratum_send_diff(ckp->sdata, client);
```

## Commit 3a6da1f
```diff
commit 3a6da1fafcb8a291e188b0ea4b1f12ddcd962395
Author: ckolivas <kernel@kolivas.org>
Date:   Fri Nov 14 13:51:06 2025 +1100

    Accept lowest diff of current and next set diff until next stratum update for maximum compatibility.

diff --git a/src/stratifier.c b/src/stratifier.c
index e7571a8..94a91e3 100644
--- a/src/stratifier.c
+++ b/src/stratifier.c
@@ -6180,9 +6180,12 @@ out_put:
 	put_workbase(sdata, wb);
 out_nowb:
 
-	/* Accept shares of the old diff until the next update */
+	/* Accept shares of the old diff until the next update. Strictly
+	 * speaking clients should not use the new diff until the next update
+	 * but very few clients do this properly, so accept whichever is the
+	 * minimum. */
 	if (id < client->diff_change_job_id)
-		diff = client->old_diff;
+		diff = MIN(diff, client->old_diff);
 	if (!invalid) {
 		char wdiffsuffix[16];
 
```

## Commit 66db3aa
```diff
commit 66db3aa3bee9f373b26c33215053627241655674
Author: ckolivas <kernel@kolivas.org>
Date:   Tue Feb 3 08:47:16 2026 +1100

    Adjust diff on the 1 minute rolling average if shares are coming in much faster than the current diff setting, to deal better with bursty hashers and hashrates significantly above the default diff.

diff --git a/src/stratifier.c b/src/stratifier.c
index 20e4b16..d5c21de 100644
--- a/src/stratifier.c
+++ b/src/stratifier.c
@@ -5654,7 +5654,6 @@ static void add_submit(ckpool_t *ckp, stratum_instance_t *client, const double d
 
 	client->ssdc++;
 	bdiff = sane_tdiff(&now_t, &client->first_share);
-	bias = time_bias(bdiff, 300);
 	tdiff = sane_tdiff(&now_t, &client->ldc);
 
 	/* Check the difficulty every 240 seconds or as many shares as we
@@ -5667,8 +5666,17 @@ static void add_submit(ckpool_t *ckp, stratum_instance_t *client, const double d
 		return;
 	}
 
-	/* Diff rate ratio */
-	dsps = client->dsps5 / bias;
+	/* Diff rate ratio.
+	 * If shares are coming in fast, calculate based on
+	 * the one minute rolling average for quick diff adjustment, otherwise
+	 * use the 5 minute rolling average */
+	if (client->ssdc >= 72) {
+		bias = time_bias(bdiff, 60);
+		dsps = client->dsps1 / bias;
+	} else {
+		bias = time_bias(bdiff, 300);
+		dsps = client->dsps5 / bias;
+	}
 	drr = dsps / (double)client->diff;
 
 	/* Optimal rate product is 0.3, allow some hysteresis. */
```

## Commit 130c755
```diff
commit 130c755d79b5242466e8dc80f87ed19244aa5f00
Author: Jaroslav (Jerry) Langer <jaroslav.langer@braiins.cz>
Date:   Mon Feb 2 01:04:06 2026 +0100

    Fix unlikely segfault from fopen error.

diff --git a/src/stratifier.c b/src/stratifier.c
index d5c21de..2c28a9a 100644
--- a/src/stratifier.c
+++ b/src/stratifier.c
@@ -8164,8 +8164,11 @@ static void *statsupdate(void *arg)
 
 		ASPRINTF(&fname, "%s/pool/pool.status", ckp->logdir);
 		fp = fopen(fname, "we");
-		if (unlikely(!fp))
+		if (unlikely(!fp)) {
 			LOGERR("Failed to fopen %s", fname);
+			dealloc(fname);
+			goto out_status;
+		}
 		dealloc(fname);
 
 		JSON_CPACK(val, "{si,si,si,si,si,si}",
@@ -8213,6 +8216,7 @@ static void *statsupdate(void *arg)
 		dealloc(s);
 		fclose(fp);
 
+out_status:
 		if (ckp->proxy && sdata->proxy) {
 			proxy_t *proxy, *proxytmp, *subproxy, *subtmp;
 
```

