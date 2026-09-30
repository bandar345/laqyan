-- =============================================================================
-- LaqYan (لقيان) — demo data: the 24 sample reports from index.html (SEED array),
-- with their drawings (illustration), English texts, and the 4 already-returned items.
-- Run AFTER the migration. Safe to re-run: it only inserts when the table is empty.
-- The admin "restore sample data" button calls the same function.
-- =============================================================================

create or replace function private.load_demo_items()
returns void
language sql
security definer
set search_path = ''
as $$
insert into public.items
  (report_type, section, item_name, category, location, item_date, description, contact_info,
   illustration, name_en, description_en, status, returned_date)
values
  ('lost',  'male',   'سماعات AirPods Pro بيضاء', 'headphones', 'كلية الحاسب والمعلومات', '2026-09-24',
   'سماعات AirPods Pro مع العلبة البيضاء، فُقدت بالقرب من القاعة B12 بعد المحاضرة الثانية.', '0555123478',
   'airpods-pro', 'White AirPods Pro', 'AirPods Pro in the white case, lost near hall B12 after the second lecture.', 'open', null),
  ('found', 'male',   'مفاتيح بميدالية جلدية بنية', 'keys', 'المكتبة المركزية', '2026-09-25',
   'مجموعة من 3 مفاتيح مربوطة بميدالية جلدية بنية، وُجدت على طاولة القراءة بالطابق الثاني.', '0561239087',
   'keys-leather', 'Keys on a brown leather tag', 'A set of 3 keys on a brown leather keychain, found on a reading table on the second floor.', 'open', null),
  ('lost',  'male',   'شاحن لابتوب Dell أسود', 'charger', 'كلية الهندسة', '2026-09-23',
   'شاحن لابتوب Dell أسود بسلك طويل، نسيته بجانب مقعد في مدرج قسم الحاسب.', '0509887654',
   'charger-usbc', 'Black Dell laptop charger', 'Black Dell laptop charger with a long cable, left next to a seat in the Computer department lecture hall.', 'returned', '2026-09-25'),
  ('found', 'female', 'محفظة جلدية سوداء', 'wallet', 'الكافتيريا الرئيسية', '2026-09-26',
   'محفظة جلد أسود تحتوي على بطاقات فقط دون نقود، وُجدت أسفل أحد الطاولات.', 'laqyan.finder1@student.ksu.edu.sa',
   'wallet-black', 'Black leather wallet', 'Black leather wallet holding cards only, no cash. Found under one of the tables.', 'returned', '2026-09-27'),
  ('lost',  'female', 'بطاقة جامعية (هوية طالبة)', 'wallet', 'المركز الطلابي', '2026-09-22',
   'بطاقتي الجامعية سقطت مني على الأغلب بالقرب من صالة الأنشطة الطلابية.', '0533221190',
   'id-card', 'University ID card (female student)', 'My university ID card — I probably dropped it near the student activities hall.', 'open', null),
  ('found', 'male',   'آيباد رمادي بكفر أزرق', 'electronics', 'مسجد الجامعة', '2026-09-25',
   'جهاز آيباد باللون الرمادي داخل كفر أزرق، وُجد في رف الأحذية بمصلى الطلاب.', '0577654321',
   'ipad-blue', 'Grey iPad in a blue case', 'Grey iPad in a blue case, found on the shoe rack in the students'' prayer room.', 'returned', '2026-09-26'),
  ('lost',  'male',   'جاكيت رياضي أسود L', 'clothing', 'صالة الرياضة', '2026-09-21',
   'جاكيت رياضي أسود مقاس L عليه شعار صغير، تركته على أحد المقاعد بعد التمرين.', '0512340098',
   'jacket-black', 'Black sports jacket, size L', 'Black size-L sports jacket with a small logo, left on a bench after training.', 'open', null),
  ('found', 'female', 'باوربانك أبيض Anker', 'electronics', 'مواقف الطلاب', '2026-09-26',
   'باوربانك أبيض من نوع Anker، وُجد على الأرض بالقرب من مدخل موقف الطالبات.', 'laqyan.finder2@student.ksu.edu.sa',
   'powerbank', 'White Anker power bank', 'White Anker power bank, found on the ground near the female students'' parking entrance.', 'open', null),
  ('lost',  'female', 'مظلة سوداء قابلة للطي', 'other', 'البوابة الرئيسية', '2026-09-20',
   'مظلة سوداء صغيرة قابلة للطي، على الأغلب نسيتها عند البوابة الرئيسية صباحًا.', '0544009911',
   'umbrella', 'Black folding umbrella', 'Small black folding umbrella, probably left at the main gate in the morning.', 'returned', '2026-09-24'),
  ('found', 'male',   'سماعة أذن واحدة (يمين)', 'headphones', 'كلية العلوم', '2026-09-24',
   'سماعة أذن لاسلكية واحدة سوداء (الجهة اليمنى فقط)، وُجدت في ممر مبنى ٤.', '0521987765',
   'earbud-black', 'Single earbud (right)', 'One black wireless earbud (right side only), found in the Building 4 corridor.', 'open', null),
  ('lost',  'female', 'نظارة طبية بإطار ذهبي', 'other', 'كلية العلوم', '2026-09-25',
   'نظارة طبية بإطار ذهبي رفيع داخل علبة بيج، فُقدت في معمل الكيمياء بالدور الأول.', '0538807766',
   'glasses-gold', 'Gold-framed prescription glasses', 'Prescription glasses with a thin gold frame in a beige case, lost in the first-floor chemistry lab.', 'open', null),
  ('found', 'female', 'سماعات Beats وردية', 'headphones', 'المكتبة المركزية', '2026-09-26',
   'سماعات رأس Beats باللون الوردي، وُجدت في قاعة المذاكرة الجماعية.', 'laqyan.finder3@student.ksu.edu.sa',
   'headphones-pink', 'Pink Beats headphones', 'Pink Beats over-ear headphones, found in the group study room.', 'open', null),
  ('lost',  'male',   'مفتاح سيارة تويوتا', 'keys', 'مواقف الطلاب', '2026-09-26',
   'مفتاح سيارة تويوتا بريموت أسود وميدالية نادي الهلال، سقط غالبًا بين الموقف والبوابة.', '0559034411',
   'car-key', 'Toyota car key', 'Toyota car key with a black remote and an Al-Hilal keychain, probably dropped between the car park and the gate.', 'open', null),
  ('lost',  'male',   'ساعة Apple Watch سوداء', 'electronics', 'صالة الرياضة', '2026-09-25',
   'ساعة Apple Watch بسوار رياضي أسود، خلعتها قبل التمرين ونسيتها في غرفة الملابس.', '0547710023',
   'smart-watch', 'Black Apple Watch', 'Apple Watch with a black sport band — took it off before training and left it in the changing room.', 'open', null),
  ('lost',  'male',   'محفظة بنية فيها بطاقة بنك', 'wallet', 'كلية إدارة الأعمال', '2026-09-19',
   'محفظة جلد بني صغيرة فيها بطاقة بنكية وبطاقة الجامعة، فُقدت في قاعة 2A.', '0503348890',
   'wallet-brown', 'Brown wallet with a bank card', 'Small brown leather wallet with a bank card and university ID, lost in room 2A.', 'open', null),
  ('found', 'male',   'شاحن آيفون أبيض مع رأس', 'charger', 'الكافتيريا الرئيسية', '2026-09-26',
   'شاحن آيفون أصلي (سلك ورأس) كان موصولًا بالفيش بجانب الطاولات القريبة من النافذة.', '0566120087',
   'phone-charger', 'White iPhone charger with plug', 'Original iPhone charger (cable and plug), found plugged in by the tables near the window.', 'open', null),
  ('found', 'male',   'شماغ أحمر', 'clothing', 'مسجد الجامعة', '2026-09-24',
   'شماغ أحمر مطوي وُجد بعد صلاة الظهر عند المدخل الشرقي للمسجد.', '0531190045',
   'shemagh-red', 'Red shemagh', 'Folded red shemagh found after Dhuhr prayer at the mosque''s east entrance.', 'open', null),
  ('found', 'male',   'آلة حاسبة Casio fx-991', 'other', 'كلية الهندسة', '2026-09-23',
   'آلة حاسبة علمية Casio عليها ملصق باسم مختصر، وُجدت في قاعة الاختبارات بعد الاختبار الفصلي.', 'laqyan.finder4@student.ksu.edu.sa',
   'calculator', 'Casio fx-991 calculator', 'Casio scientific calculator with a name sticker, found in the exam hall after the midterm.', 'open', null),
  ('lost',  'female', 'عباية سوداء مطرزة', 'clothing', 'المركز الطلابي', '2026-09-24',
   'عباية سوداء بتطريز ذهبي على الأكمام، تركتها في غرفة الأنشطة بعد الفعالية.', '0556678812',
   'abaya', 'Embroidered black abaya', 'Black abaya with gold embroidery on the sleeves, left in the activities room after the event.', 'open', null),
  ('lost',  'female', 'لابتوب MacBook Air فضي', 'electronics', 'كلية الحاسب والمعلومات', '2026-09-26',
   'لابتوب MacBook Air فضي عليه ملصقات زهور، داخل غطاء وردي، فُقد في معمل البرمجة 3.', '0549902231',
   'laptop-stickers', 'Silver MacBook Air', 'Silver MacBook Air with flower stickers in a pink sleeve, lost in programming lab 3.', 'open', null),
  ('lost',  'female', 'سماعات Galaxy Buds بيضاء', 'headphones', 'الكافتيريا الرئيسية', '2026-09-23',
   'سماعات Samsung Galaxy Buds داخل علبة بيضاء، تركتها على الطاولة وقت الاستراحة.', '0534417789',
   'buds-white', 'White Galaxy Buds', 'Samsung Galaxy Buds in a white case, left on a table during the break.', 'open', null),
  ('found', 'female', 'مفاتيح مع ميدالية فراشة', 'keys', 'كلية إدارة الأعمال', '2026-09-25',
   'مفتاحان مع ميدالية فراشة بنفسجية، وُجدت على الدرج المؤدي للدور الثاني.', '0567743320',
   'keys-butterfly', 'Keys with a butterfly keychain', 'Two keys with a purple butterfly keychain, found on the stairs to the second floor.', 'open', null),
  ('found', 'female', 'شاحن لابتوب HP', 'charger', 'كلية العلوم', '2026-09-22',
   'شاحن لابتوب HP أسود بسلك قصير، وُجد في قاعة المحاضرات الكبرى بعد نهاية اليوم.', 'laqyan.finder5@student.ksu.edu.sa',
   'charger-barrel', 'HP laptop charger', 'Black HP laptop charger with a short cable, found in the main lecture hall at the end of the day.', 'open', null),
  ('found', 'female', 'بطاقة مكافأة جامعية', 'wallet', 'البوابة الرئيسية', '2026-09-21',
   'بطاقة صرف مكافأة باسم طالبة، وُجدت على الأرض بجانب بوابة الدخول الرئيسية صباحًا.', '0512239908',
   'bank-card', 'University allowance card', 'A student''s allowance card, found on the ground next to the main entrance gate in the morning.', 'open', null);
$$;

revoke all on function private.load_demo_items() from public, anon, authenticated;

-- Load the demo items once (does nothing if reports already exist).
select private.load_demo_items() where not exists (select 1 from public.items);
