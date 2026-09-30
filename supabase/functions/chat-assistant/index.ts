// LaqYan (لقيان) — "مساعد لقيان" chat agent.
//
// POST { message, history: [{role:'user'|'model', text}], section: 'male'|'female' }
//  ->  { reply, items: [id…], created: row|null }    or    { error: code, reply }
//
// Gemini (function calling) decides what to do; the two tools below run here, server-side,
// with the project's secret key. The browser never sees the Gemini key or the secret key.
//
// Secrets:  GEMINI_API_KEY (required)   GEMINI_MODEL (optional, default below)
import { createClient } from 'npm:@supabase/supabase-js@2';

// Tried in order when a model is overloaded, out of quota or slow; GEMINI_MODEL (if set) goes first.
// (Quotas are per model, so the next one usually still works.)
const MODELS = [...new Set([Deno.env.get('GEMINI_MODEL'), 'gemini-3.5-flash', 'gemini-3.5-flash-lite', 'gemini-3.8-flash'].filter(Boolean))] as string[];
const geminiUrl = (model: string) => `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
const MAX_TOOL_ROUNDS = 5;
const CALL_TIMEOUT_MS = 30000;             // one Gemini call; slower counts as overloaded
const MAX_MESSAGE = 600, MAX_HISTORY = 10, MAX_HISTORY_TEXT = 1500;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// ---- Values that match public.items (see supabase/migrations/20260929120000_create_items.sql) ----
const CATEGORIES: Record<string, string> = {
  headphones: 'سماعات', keys: 'مفاتيح', charger: 'شاحن', wallet: 'محفظة / هوية',
  electronics: 'إلكترونيات', clothing: 'ملابس', other: 'أخرى',
};
const LOCATIONS = [
  'كلية الحاسب والمعلومات', 'كلية الهندسة', 'كلية العلوم', 'كلية إدارة الأعمال', 'المكتبة المركزية',
  'الكافتيريا الرئيسية', 'المركز الطلابي', 'مسجد الجامعة', 'صالة الرياضة', 'مواقف الطلاب',
  'البوابة الرئيسية', 'أخرى',
];
// Everyday words -> category key, so "ضاعت سماعتي" also finds items filed under headphones.
const CATEGORY_WORDS: [RegExp, string][] = [
  [/سماع|ايربود|إيربود|airpod|buds|beats|headphone/i, 'headphones'],
  [/مفتاح|مفاتيح|key/i, 'keys'],
  [/شاحن|charger|كيبل|سلك/i, 'charger'],
  [/محفظ|بطاق|هوي|كرت|wallet|card/i, 'wallet'],
  [/جوال|ايفون|آيفون|ايباد|آيباد|لابتوب|ماك|ساعة|ساعه|باوربانك|حاسب|phone|ipad|laptop|watch/i, 'electronics'],
  [/جاكيت|شماغ|عباي|غتر|ثوب|جزم|حذاء|jacket|abaya/i, 'clothing'],
];

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

function riyadhToday(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Riyadh' });   // YYYY-MM-DD
}

// Secret key for server-side DB access: new-style key first, legacy service_role as fallback.
function secretKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}');
    if (keys.default) return keys.default;
  } catch { /* fall through */ }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
}
// Only calls carrying this project's publishable (or legacy anon) key are served.
function knownClientKey(req: Request): boolean {
  const sent = req.headers.get('apikey') || (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!sent) return false;
  const allowed: string[] = [];
  try { allowed.push(...Object.values(JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') || '{}')) as string[]); } catch { /* none */ }
  const anon = Deno.env.get('SUPABASE_ANON_KEY'); if (anon) allowed.push(anon);
  return allowed.includes(sent);
}

const db = createClient(Deno.env.get('SUPABASE_URL')!, secretKey(), { auth: { persistSession: false } });

// ------------------------------------------------------------------ tools
const ITEM_COLS = 'id, report_type, section, status, item_name, category, description, location, item_date, name_en, description_en';

// Arabic-friendly search words: drop diacritics/tatweel, "ال", and common plural/feminine endings.
function searchStems(q: string): string[] {
  const words = q.replace(/[ً-ْـ]/g, '').split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  const stems = new Set<string>();
  for (let w of words) {
    w = w.replace(/^(وال|بال|لل|ال)/, '');
    if (w.length > 4) w = w.replace(/(ات|ة|ه|ي)$/, '');
    if (w.length >= 2) stems.add(w.toLowerCase());
  }
  return [...stems].slice(0, 8);
}

async function searchItems(args: { query?: string; category?: string }, section: string) {
  const query = String(args.query || '').slice(0, 200);
  const stems = searchStems(query);
  const cats = new Set<string>();
  if (args.category && CATEGORIES[args.category]) cats.add(args.category);
  for (const [re, key] of CATEGORY_WORDS) if (re.test(query)) cats.add(key);

  const ors: string[] = [];
  for (const s of stems) for (const col of ['item_name', 'description', 'location', 'name_en', 'description_en']) ors.push(`${col}.ilike.*${s}*`);
  for (const c of cats) ors.push(`category.eq.${c}`);
  if (!ors.length) return { results: [], note: 'اكتب وصفًا للغرض للبحث.' };

  const { data, error } = await db.from('items').select(ITEM_COLS)
    .eq('report_type', 'found').eq('status', 'open').eq('section', section)
    .or(ors.join(',')).limit(60);
  if (error) { console.error('search_items', error); return { error: 'تعذّر البحث حاليًا.' }; }

  const scored = (data || []).map((r) => {
    const name = (r.item_name + ' ' + (r.name_en || '')).toLowerCase();
    const desc = (r.description + ' ' + (r.description_en || '')).toLowerCase();
    let score = cats.has(r.category) ? 3 : 0;
    for (const s of stems) {
      if (name.includes(s)) score += 3;
      if (desc.includes(s)) score += 1;
      if (r.location.includes(s)) score += 1;
    }
    return { r, score };
  }).filter((x) => x.score > 0).sort((a, b) => b.score - a.score || (a.r.item_date < b.r.item_date ? 1 : -1)).slice(0, 5);

  return {
    section: section === 'female' ? 'قسم الطالبات' : 'قسم الطلاب',
    results: scored.map(({ r, score }) => ({
      id: r.id, item_name: r.item_name, category: CATEGORIES[r.category] || r.category,
      description: r.description, location: r.location, found_on: r.item_date, relevance: score,
    })),
  };
}

function validContact(v: string): boolean {
  const s = v.replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d))).replace(/[\s-]/g, '');
  return /^(05\d{8}|(\+|00)9665\d{8})$/.test(s) || /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(v.trim());
}

async function createLostReport(a: Record<string, unknown>, fallbackSection: string) {
  const v = {
    item_name: String(a.item_name || '').trim(), category: String(a.category || ''),
    description: String(a.description || '').trim(), location: String(a.location || ''),
    item_date: String(a.item_date || ''), contact_info: String(a.contact_info || '').trim(),
    section: a.section === 'male' || a.section === 'female' ? String(a.section) : fallbackSection,
  };
  // Same rules as the app's report form.
  const errors: string[] = [];
  if (!v.item_name || v.item_name.length > 120) errors.push('اسم الغرض مطلوب (حتى 120 حرفًا)');
  if (!CATEGORIES[v.category]) errors.push('التصنيف غير صحيح');
  if (!v.description) errors.push('الوصف مطلوب');
  if (v.description.length > 2000) errors.push('الوصف طويل جدًا');
  if (!LOCATIONS.includes(v.location)) errors.push('الموقع يجب أن يكون من القائمة');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v.item_date) || v.item_date < '2020-01-01' || v.item_date > riyadhToday()) errors.push('التاريخ غير صحيح أو في المستقبل');
  if (!validContact(v.contact_info)) errors.push('وسيلة التواصل: رقم جوال سعودي (05xxxxxxxx) أو بريد إلكتروني');
  if (errors.length) return { ok: false, errors };

  const { data, error } = await db.from('items').insert({ report_type: 'lost', status: 'open', ...v }).select().single();
  if (error) { console.error('create_lost_report', error); return { ok: false, errors: ['تعذّر حفظ البلاغ، حاول مرة أخرى'] }; }
  return { ok: true, row: data };
}

const TOOLS = [{
  functionDeclarations: [
    {
      name: 'search_items',
      description: 'يبحث في بلاغات "الموجودات" المفتوحة (أغراض لقاها أحد وسلّمها) في قسم الطالب الحالي. استخدمه قبل أي حكم على وجود الغرض.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'كلمات وصف الغرض بالعربي: النوع، اللون، الماركة، المكان. مثال: "سماعات ايربودز بيضاء"' },
          category: { type: 'string', enum: Object.keys(CATEGORIES), description: 'تصنيف الغرض إن كان واضحًا' },
        },
        required: ['query'],
      },
    },
    {
      name: 'create_lost_report',
      description: 'يسجّل بلاغ مفقود جديد. لا تستخدمه إلا بعد أن تلخّص البيانات للطالب ويؤكد صراحةً (مثل: نعم / أكّد / سجّل).',
      parameters: {
        type: 'object',
        properties: {
          item_name: { type: 'string', description: 'اسم الغرض المختصر، مثل: "سماعات AirPods بيضاء"' },
          category: { type: 'string', enum: Object.keys(CATEGORIES), description: Object.entries(CATEGORIES).map(([k, v]) => `${k}=${v}`).join('، ') },
          description: { type: 'string', description: 'وصف مختصر: اللون، العلامات المميزة، وأين ومتى تقريبًا' },
          location: { type: 'string', enum: LOCATIONS, description: 'أقرب موقع من القائمة؛ "أخرى" إن لم يطابق شيء' },
          item_date: { type: 'string', description: 'تاريخ الفقدان بصيغة YYYY-MM-DD (لا يكون في المستقبل)' },
          contact_info: { type: 'string', description: 'جوال سعودي 05xxxxxxxx أو بريد إلكتروني' },
          section: { type: 'string', enum: ['male', 'female'], description: 'قسم الطالب' },
        },
        required: ['item_name', 'category', 'description', 'location', 'item_date', 'contact_info', 'section'],
      },
    },
  ],
}];

function systemPrompt(section: string): string {
  const sec = section === 'female' ? 'قسم الطالبات (female)' : 'قسم الطلاب (male)';
  return `أنت "مساعد لقيان"، المساعد الأول لأي طالب يفتح تطبيق لقيان للمفقودات والموجودات في جامعة الملك سعود. مهمتك مساعدة الطالب يلقى غرضه المفقود.
- أول شي حاول تجاوب من بيانات الموجودات الفعلية عن طريق أداة البحث search_items، ما تخمن ولا تختلق نتائج.
- اسأل عن تفاصيل الغرض إذا كانت الرسالة غامضة (وش نوعه، وين تقريبًا ضاع، متى) قبل ما تبحث.
- إذا لقيت تطابق محتمل واحد أو أكثر، اعرضه بوضوح (اسم الغرض كما هو في النتائج بالضبط، الموقع، التاريخ) واسأل الطالب هل هذا غرضه. إذا قال نعم: يضغط على بطاقة البلاغ اللي تظهر تحت رسالتك ثم زر «هذا الغرض لي — عرض بيانات التواصل» ويتواصل مع اللي لقاه.
- إذا ما فيه أي تطابق مناسب، وضح للطالب إنه ما فيه بلاغ مطابق حاليًا، واعرض عليه تسجّل بلاغ مفقود بدلاً منه.
- لتسجيل البلاغ، اجمع الحقول الناقصة بس (اسم الغرض، التصنيف، الوصف، الموقع، التاريخ، وسيلة التواصل)، لخّصها للطالب واطلب تأكيد صريح قبل ما تستخدم أداة create_lost_report. لا تسأل عن شي قاله الطالب من قبل.
- الموقع لازم يكون من قائمة المواقع؛ إذا ذكر الطالب مكان مو في القائمة اختر الأقرب أو "أخرى" واذكر المكان في الوصف.
- التواريخ النسبية (أمس، الأحد اللي فات) حوّلها لتاريخ فعلي. تاريخ اليوم: ${riyadhToday()} (توقيت الرياض).
- الطالب حاليًا في ${sec}؛ ابحث وسجّل في هذا القسم.
- إذا رجعت الأداة أخطاء تحقق، اطلب من الطالب تصحيح الحقل المعني فقط.
- بعد تسجيل البلاغ بنجاح، أكّد له بجملة قصيرة إن البلاغ انضاف لقائمة المفقودات.
- لا تذكر معرّفات البلاغات (id) ولا تفاصيل تقنية، ولا تجاوب على مواضيع خارج المفقودات والموجودات في الجامعة.
- ردودك دائمًا بالعربي، قصيرة، ودودة، ومباشرة، بدون حشو. نص عادي بدون جداول.`;
}

// ------------------------------------------------------------------ Gemini
class GeminiError extends Error { constructor(public code: string, msg: string) { super(msg); } }

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function callModel(model: string, contents: unknown[], section: string) {
  const started = Date.now();
  const res = await fetch(geminiUrl(model), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': Deno.env.get('GEMINI_API_KEY')! },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: systemPrompt(section) }] },
      contents, tools: TOOLS,
      // Low thinking keeps each call to a few seconds; plenty for search + form filling.
      generationConfig: { temperature: 0.3, maxOutputTokens: 1024, thinkingConfig: { thinkingLevel: 'low' } },
    }),
    signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
  }).catch((e) => {
    if (e?.name === 'TimeoutError' || e?.name === 'AbortError') {
      console.error('gemini', model, 'timeout', CALL_TIMEOUT_MS);
      throw new GeminiError('busy', `timeout after ${CALL_TIMEOUT_MS}ms`);
    }
    throw e;
  });
  if (res.ok) { console.log('gemini', model, 'ok', Date.now() - started, 'ms'); return await res.json(); }
  const text = await res.text();
  console.error('gemini', model, res.status, text.slice(0, 300));
  if (res.status === 429) throw new GeminiError('rate_limited', text);
  if (res.status === 400 && /API key/i.test(text) || res.status === 401 || res.status === 403) throw new GeminiError('not_configured', text);
  // Overloaded / model not available to this key -> the caller may try another model.
  if (res.status === 503 || res.status === 500 || res.status === 404) throw new GeminiError('busy', text);
  throw new GeminiError('upstream', text);
}

// First round: the first model that answers wins (overloaded / out of quota / slow -> next one).
// Later rounds of the same message stay on that model, since its thought signatures only
// validate there; it gets one short retry.
async function gemini(contents: unknown[], section: string, pinned: { model?: string }) {
  if (!Deno.env.get('GEMINI_API_KEY')) throw new GeminiError('not_configured', 'GEMINI_API_KEY is not set');
  const retriable = (e: unknown) => e instanceof GeminiError && (e.code === 'busy' || e.code === 'rate_limited');
  if (pinned.model) {
    try { return await callModel(pinned.model, contents, section); }
    catch (e) { if (!retriable(e)) throw e; await sleep(1000); return await callModel(pinned.model, contents, section); }
  }
  let last: unknown;
  for (const model of MODELS) {
    try {
      const data = await callModel(model, contents, section);
      pinned.model = model;
      return data;
    } catch (e) {
      last = e;
      if (!retriable(e)) throw e;
    }
  }
  throw last;
}

const FALLBACK: Record<string, string> = {
  rate_limited: 'المساعد مشغول حاليًا من كثرة الطلبات. جرّب بعد دقيقة، أو استخدم زر «الإبلاغ عن مفقود» مباشرة.',
  busy: 'خدمة الذكاء الاصطناعي عليها ضغط كبير الحين. جرّب بعد شوي، أو استخدم زر «الإبلاغ عن مفقود» مباشرة.',
  not_configured: 'المساعد غير مفعّل حاليًا. تقدر تبحث في القائمة أو تستخدم زر «الإبلاغ عن مفقود».',
  upstream: 'صار خلل مؤقت عند المساعد. حاول مرة ثانية بعد لحظات.',
  bad_request: 'ما قدرت أفهم الرسالة، جرّب تكتبها مرة ثانية.',
};

// ------------------------------------------------------------------ handler
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'bad_request', reply: FALLBACK.bad_request }, 405);
  if (!knownClientKey(req)) return json({ error: 'unauthorized' }, 401);

  let body: { message?: unknown; history?: unknown; section?: unknown };
  try { body = await req.json(); } catch { return json({ error: 'bad_request', reply: FALLBACK.bad_request }, 400); }
  const message = typeof body.message === 'string' ? body.message.trim().slice(0, MAX_MESSAGE) : '';
  if (!message) return json({ error: 'bad_request', reply: FALLBACK.bad_request }, 400);
  const section = body.section === 'female' ? 'female' : 'male';
  const history = (Array.isArray(body.history) ? body.history : []).slice(-MAX_HISTORY)
    .filter((m: any) => m && (m.role === 'user' || m.role === 'model') && typeof m.text === 'string' && m.text.trim())
    .map((m: any) => ({ role: m.role, parts: [{ text: m.text.slice(0, MAX_HISTORY_TEXT) }] }));

  const contents: any[] = [...history, { role: 'user', parts: [{ text: message }] }];
  const seen = new Map<string, string>();          // id -> item_name, from this turn's searches
  let created: Record<string, unknown> | null = null;
  const pinned: { model?: string } = {};

  try {
    for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
      const data = await gemini(contents, section, pinned);
      const cand = data.candidates?.[0];
      const parts: any[] = cand?.content?.parts || [];
      const calls = parts.filter((p) => p.functionCall);

      if (!calls.length || round === MAX_TOOL_ROUNDS) {
        const reply = parts.filter((p) => typeof p.text === 'string' && !p.thought).map((p) => p.text).join('').trim()
          || (created ? 'تم تسجيل بلاغك بنجاح ✅' : 'ما قدرت أجهّز رد مناسب، ممكن توضّح أكثر؟');
        // Item cards for the UI: search results the reply actually names.
        const items = [...seen].filter(([, name]) => reply.includes(name)).map(([id]) => id);
        return json({ reply, items, created, model: pinned.model });
      }

      contents.push(cand.content);                 // keep the model turn as-is (incl. thought signatures)
      const responses = [];
      for (const p of calls) {
        const { name, args = {}, id } = p.functionCall;
        let result: unknown;
        if (name === 'search_items') {
          result = await searchItems(args, section);
          for (const r of (result as any).results || []) seen.set(r.id, r.item_name);
        } else if (name === 'create_lost_report') {
          if (created) result = { ok: false, errors: ['تم تسجيل بلاغ بالفعل في هذه الرسالة'] };
          else {
            const out = await createLostReport(args, section);
            if (out.ok) { created = out.row; result = { ok: true, message: 'تم حفظ البلاغ في قائمة المفقودات' }; }
            else result = out;
          }
        } else result = { error: 'unknown tool' };
        responses.push({ functionResponse: { name, ...(id ? { id } : {}), response: { result } } });
      }
      contents.push({ role: 'user', parts: responses });
    }
  } catch (e) {
    const code = e instanceof GeminiError ? e.code : 'upstream';
    if (!(e instanceof GeminiError)) console.error('chat-assistant', e);
    // A report saved before the failure still counts — tell the client so it can show it.
    return json({ error: code, reply: created ? 'تم تسجيل بلاغك بنجاح ✅' : FALLBACK[code], created }, 200);
  }
  return json({ error: 'upstream', reply: FALLBACK.upstream }, 200);
});
