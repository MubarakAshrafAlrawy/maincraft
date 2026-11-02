# Content packs

كل ما يخص البلوكات والنسيج أصبح خارج الكود:

```
content/
  base/
    pack.json
    blocks.json
    textures/
      stone.png
      grass_top.png
      ...
```

المحرّك يقرأ كل مجلد داخل `content/`، وكل مجلد داخل `user://packs/`، ثم يدمجها بالترتيب.
آخر باك يملك الأولوية، لذلك يمكنك إضافة باك يعدّل نسيج بلوك موجود دون لمس الكود.

## 1. إضافة بلوك جديد

أنشئ مجلدًا مثل `content/mypack/` وضع فيه:

`pack.json`

```json
{
  "name": "My Pack",
  "order": 100,
  "tile_size": 16
}
```

`blocks.json`

```json
{
  "format": 1,
  "blocks": [
    {
      "name": "Marble",
      "textures": { "all": "marble" },
      "hardness": 1.8,
      "tool": "pickaxe",
      "tier": "stone",
      "drops": "Marble"
    }
  ]
}
```

`textures/marble.png` (16×16 أو أي مقاس، وسيُصغَّر إلى `tile_size`).

لا حاجة لكتابة `id`: سيأخذ أول رقم حر. إذا أردت ربطه بحفظ عالم قديم فاكتب `"id": 19` صراحةً.

## 2. استبدال نسيج بلوك موجود

انسخ صورة بنفس الاسم إلى باك متأخر:

```
content/mytextures/pack.json      { "order": 200 }
content/mytextures/textures/stone.png
content/mytextures/textures/grass_top.png
```

لا تحتاج `blocks.json` إطلاقًا. اسم النسيج هو اسم الملف بدون الامتداد، أو المسار النسبي داخل
`textures/` مثل `"minecraft/stone"` إذا استخدمت مجلدات فرعية.

## 3. مخطط البلوك

| الحقل | النوع | الوصف |
|---|---|---|
| `name` | String | مطلوب وفريد. هو أيضًا اسم العنصر في المخزون. |
| `id` | int | اختياري. ثابت للحفظ. لا تغيّر أرقام البلوكات القديمة. |
| `textures` | String أو Object | اسم نسيج واحد، أو خريطة أوجه. |
| `transparent` | bool | يُرسم النسيج الشفاف (أوراق، نباتات). |
| `passable` | bool | يمكن المرور عبره (بدون تصادم). |
| `flat` | bool | نبات بشكل X بدل مكعب كامل. |
| `liquid` | bool | علامة سائل. |
| `replaceable` | bool | يمكن وضع بلوك فوقه/داخله (ماء، نبات). |
| `hardness` | float | ثوانٍ باليد. صفر = كسر فوري. |
| `tool` | String | `hand`, `pickaxe`, `axe`, `shovel`, `sword`, `shears`, `hoe`. |
| `tier` | String | `any`, `wood`, `stone`, `iron`, `gold`, `diamond`, `netherite`. |
| `drops` | String | اسم البلوك المتساقط. تركه فارغًا يعني «نفسه». |
| `light` | int | 0..15 (محجوز للإضاءة لاحقًا). |

### الأوجه

```json
"textures": {
  "top": "grass_top",
  "bottom": "dirt",
  "side": "grass_side"
}
```

المفاتيح المدعومة: `all`, `only`, `top`, `bottom`, `side`, `left`, `right`, `front`, `back`.
`only` للنباتات المسطّحة، وأي وجه غير محدد يرجع إلى `all`/`only`.

## 4. أين تُثبَّت الباكات؟

- داخل المشروع: `content/<pack>/` — تظهر في المحرّر وتُصدَّر مع اللعبة.
- بعد التصدير: `user://packs/<pack>/` — يُنشأ المجلد تلقائيًا في أول تشغيل، ومعه `README.txt`.
  على Windows يكون عادة:
  `%APPDATA%\Godot\app_userdata\maincraft\packs\`

## 5. ملاحظات مهمة

- **ثبات الأرقام**: `id` هو ما يُخزَّن في العالم وفي الحفظ لاحقًا. أضف دائمًا في النهاية،
  ولا تعد ترتيب `content/base/blocks.json`.
- **مقاس النسيج**: `tile_size` في `pack.json` الخاص بالباك الأساسي يحدد دقة الأطلس كله (افتراضي 16).
  الصور الأخرى تُصغَّر إليه بـ Nearest Neighbor.
- **نسيج مفقود**: يظهر مربع أرجواني/أسود مميز بدل أن تنهار اللعبة، مع تحذير في الكونسول.
- **الأطلس**: يُبنى وقت التشغيل من الصور المفردة، لذا لا تحتاج ملف أطلس ولا UVs يدوية.
- **التصدير**: أضف `*.json, *.png` إلى مرشّح التضمين في إعدادات التصدير حتى تبقى ملفات الباكات
  قابلة للقراءة من `res://content` في النسخة المصدَّرة.
- **الترخيص**: لا توزّع أصولًا (Textures) لا تملك حق استخدامها. باكات Minecraft الرسمية محمية
  بحقوق مالكها؛ استخدمها محليًا على مسؤوليتك أو استخدم باكات مرخّصة.
