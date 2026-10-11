# Online appointment setup

The website can send appointment requests to WhatsApp immediately. Until the database schema is installed and the site is deployed, chosen times are requests only—not live availability or confirmed reservations. Customers should wait for the parlour to confirm.

## 1. Create the database

1. Create a Supabase project at [supabase.com](https://supabase.com/).
2. In the project dashboard, open **SQL Editor**.
3. Copy and run the complete contents of `supabase/schema.sql`.

The database allows one booking per 2-hour time window and date. The booking function reserves a slot atomically, so simultaneous requests cannot both book the same window. Public visitors can read availability and submit bookings, but cannot read customer records. The schema also creates the customer reviews table and public functions used to display and submit reviews; reviews are published immediately.

### Reviews: save them and show them publicly

Run the complete, latest `supabase/schema.sql` in the SQL Editor of the same Supabase project configured in `supabase-client.js`. This creates `public.customer_reviews` and the `get_customer_reviews` and `submit_customer_review` functions. The website sends new reviews to the submit function, which stores the name, 1–5 star rating, review text, and submission time in the database. It loads the newest reviews through the read function and shows them to every visitor.

The review table itself is not directly readable or writable by public visitors. The two database functions provide the restricted public interface: visitors may submit validated reviews and read the latest 100 reviews. Submissions are published immediately without moderation. After running the SQL, reload the site and try submitting a review; it should appear in the public list. If the site still reports that the review database needs setup, confirm the SQL ran successfully in this project and wait briefly for the Supabase API schema cache to refresh, then reload.

There is no admin login or admin page. The owner can securely view appointments in the Supabase dashboard under **Table Editor → appointments**. Use the dashboard to cancel a booking (change its status to `cancelled` to release the slot) or to manage rows in `blocked_slots`. Do not expose dashboard credentials to customers.

## 2. Configure the public website key

The project URL and publishable key are configured in `supabase-client.js`. Never put a `service_role` or secret key in browser code.

If the live availability or review functions are missing from the project's API schema cache, run the latest `supabase/schema.sql` in the Supabase **SQL Editor** (Step 1) and allow the API schema cache to refresh. Reload the website to test availability and reviews.

## 3. Deploy the website

Deploy this whole folder to a static web host with HTTPS, keeping `index.html`, `supabase-client.js`, and the `supabase` folder together. `localhost:3000` is only available on the computer running the local server; it is not an online address other customers can use.

If the Supabase project restricts allowed origins, add the deployed website's origin in the project's API/CORS settings. Test a booking on one browser/device and confirm the same date/time appears as booked on another. To cancel or block a slot, use the Supabase dashboard.

Appointment submissions are public, so add CAPTCHA or equivalent rate limiting before promoting the form broadly to reduce automated spam.

Review submissions are also public and published immediately. Review entries contain only the name provided by the customer, their star rating, review text, and submission time. Add CAPTCHA or equivalent rate limiting before promoting the review form broadly to reduce spam.
