// Use the project's public URL and publishable (or legacy anon) key here.
// Never put a Supabase service-role key in browser code.
const SUPABASE_URL = "https://bvwqyimpymfhuqdtjnua.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_g2NcEGP5DUpzNxohbyQ6Lg_UTpokq71";

const supabaseConfigured =
  /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(SUPABASE_URL) &&
  !SUPABASE_URL.includes("YOUR_PROJECT_REF") &&
  SUPABASE_ANON_KEY.length > 20 &&
  !SUPABASE_ANON_KEY.includes("YOUR_SUPABASE_");

function requireSupabaseConfig() {
  if (!supabaseConfigured) {
    throw new Error("Online appointments are not set up yet. Please call or WhatsApp the parlour.");
  }
}

async function supabaseRequest(path, { method = "POST", body, accessToken } = {}) {
  requireSupabaseConfig();

  const headers = {
    apikey: SUPABASE_ANON_KEY,
    "Content-Type": "application/json"
  };

  if (accessToken) {
    headers.Authorization = `Bearer ${accessToken}`;
  } else if (SUPABASE_ANON_KEY.startsWith("eyJ")) {
    headers.Authorization = `Bearer ${SUPABASE_ANON_KEY}`;
  }

  const response = await fetch(`${SUPABASE_URL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const responseText = await response.text();
  let responseBody = null;

  if (responseText) {
    try {
      responseBody = JSON.parse(responseText);
    } catch {
      responseBody = responseText;
    }
  }

  if (!response.ok) {
    const message =
      responseBody?.message ||
      responseBody?.msg ||
      responseBody?.error_description ||
      responseBody?.error ||
      "The booking service returned an unexpected error.";
    const error = new Error(message);
    error.code = responseBody?.code || responseBody?.error_code || "";
    throw error;
  }

  return responseBody;
}

function rpc(name, parameters, accessToken) {
  return supabaseRequest(`/rest/v1/rpc/${name}`, {
    body: parameters,
    accessToken
  });
}

window.glamourBookings = {
  configured: supabaseConfigured,

  getSlotStatus(date, accessToken) {
    return rpc("get_slot_status", { p_date: date }, accessToken);
  },

  createAppointment(appointment) {
    return rpc("create_appointment", {
      p_customer_name: appointment.name,
      p_customer_phone: appointment.phone,
      p_service: appointment.service,
      p_date: appointment.date,
      p_time_slot: appointment.time,
      p_notes: appointment.notes
    });
  },

};

window.glamourReviews = {
  getReviews() {
    return rpc("get_customer_reviews", {});
  },

  submitReview(review) {
    return rpc("submit_customer_review", {
      p_display_name: review.name,
      p_rating: review.rating,
      p_review_text: review.text
    });
  }
};
