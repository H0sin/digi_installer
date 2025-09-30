# راهنمای نصب - فارسی

## نصب سریع

### نصب خودکار (پیشنهادی)

اسکریپت نصب تعاملی را اجرا کنید:

```bash
./install.sh
```

### قابلیت‌های اسکریپت نصب

اسکریپت نصب به صورت خودکار موارد زیر را انجام می‌دهد:

✅ **بررسی سیستم:**
- بررسی پردازنده، حافظه رم و فضای دیسک
- نصب Docker و Docker Compose در صورت نیاز
- بررسی دسترسی‌های لازم

✅ **انتخاب سرویس‌ها:**
اسکریپت از شما می‌پرسد کدام سرویس‌ها را می‌خواهید نصب کنید:
- پایگاه داده PostgreSQL و PgAdmin
- صف پیام RabbitMQ
- حافظه کش Redis و Redis Insight
- ذخیره‌سازی شیء MinIO
- مدیریت Docker با Portainer
- اپلیکیشن اصلی وب
- اپلیکیشن کلاینت (React)
- سرویس پردازشگر
- سرویس کارگر سفارش
- سرویس Jobs
- پروکسی معکوس Caddy

✅ **جمع‌آوری تنظیمات:**
اسکریپت به صورت تعاملی اطلاعات زیر را جمع‌آوری می‌کند:
- نام پروژه
- دامنه اصلی و زیردامنه‌ها
- ایمیل برای گواهی SSL
- رمزهای عبور سرویس‌ها
- تنظیمات لاگ تلگرام (اختیاری)
- تعداد رپلیکاها برای مقیاس‌پذیری

✅ **استقرار خودکار:**
- تولید فایل `.env` با تنظیمات شما
- به‌روزرسانی `Caddyfile` برای دامنه‌ها
- اعتبارسنجی تنظیمات
- پشتیبان‌گیری از تنظیمات قبلی
- استقرار و راه‌اندازی سرویس‌ها

---

## سناریوهای نصب

### 1. نصب کامل (یک سرور)

برای محیط توسعه یا تولید کوچک:

```bash
./install.sh
```

به همه سوالات "Y" پاسخ دهید.

**مناسب برای:**
- محیط توسعه
- استیجینگ
- تولید کوچک تا متوسط

---

### 2. فقط سرور پایگاه داده

اگر می‌خواهید پایگاه داده روی سرور جداگانه باشد:

```bash
./install.sh
```

فقط به موارد زیر "Y" پاسخ دهید:
- PostgreSQL ✅
- PgAdmin ✅
- Portainer (اختیاری) ✅

به بقیه "N" پاسخ دهید.

**نکته مهم:**
- پورت 5432 را برای سرورهای اپلیکیشن باز کنید
- از رمز عبور قوی استفاده کنید
- فایروال را به درستی تنظیم کنید

---

### 3. فقط سرور اپلیکیشن

برای مقیاس‌پذیری افقی:

```bash
./install.sh
```

به موارد زیر "N" پاسخ دهید:
- PostgreSQL ❌
- PgAdmin ❌
- RabbitMQ ❌ (اگر از سرور خارجی استفاده می‌کنید)
- Redis ❌ (اگر از سرور خارجی استفاده می‌کنید)
- MinIO ❌ (اگر از سرور خارجی استفاده می‌کنید)

به موارد زیر "Y" پاسخ دهید:
- اپلیکیشن وب اصلی ✅
- اپلیکیشن کلاینت ✅
- سرویس پردازشگر ✅
- سرویس کارگر ✅
- سرویس Jobs ✅
- Caddy ✅

**پیکربندی:**
هنگام وارد کردن اطلاعات پایگاه داده، از آدرس سرور خارجی استفاده کنید.

---

### 4. محیط توسعه

تنظیمات بهینه برای توسعه‌دهندگان:

```bash
./install.sh
```

**پیشنهادات:**
- همه سرویس‌ها را نصب کنید
- تعداد رپلیکا کم: 1-2
- از دامنه `.local` یا `.test` استفاده کنید
- همه رابط‌های مدیریتی را فعال کنید

**افزودن دامنه محلی:**
```bash
echo "127.0.0.1 myapp.local" | sudo tee -a /etc/hosts
echo "127.0.0.1 client.myapp.local" | sudo tee -a /etc/hosts
```

---

### 5. محیط تولید

تنظیمات بهینه برای تولید:

**پیش از نصب:**
- [ ] DNS را پیکربندی کنید
- [ ] رمزهای عبور قوی (حداقل 16 کاراکتر) آماده کنید
- [ ] ایمیل معتبر برای Let's Encrypt داشته باشید
- [ ] منابع سرور کافی (4GB RAM، 4 CPU) داشته باشید

**نصب:**
```bash
./install.sh
```

**تنظیمات پیشنهادی:**
- تعداد رپلیکا پردازشگر: 5-10
- تعداد رپلیکا کارگر: 2-5
- لاگ تلگرام فعال
- گواهی SSL خودکار

**بعد از نصب:**
- [ ] وضعیت سرویس‌ها را بررسی کنید
- [ ] گواهی SSL را تست کنید
- [ ] فایروال را تنظیم کنید
- [ ] استراتژی پشتیبان‌گیری را راه‌اندازی کنید
- [ ] مانیتورینگ را فعال کنید

---

## دستورات مفید

### بررسی وضعیت سرویس‌ها:
```bash
docker compose ps
```

### مشاهده لاگ‌ها:
```bash
# همه سرویس‌ها
docker compose logs -f

# یک سرویس خاص
docker compose logs -f webapp
docker compose logs -f postgres
docker compose logs -f rabbitmq
```

### راه‌اندازی مجدد:
```bash
# همه سرویس‌ها
docker compose restart

# یک سرویس خاص
docker compose restart webapp
```

### متوقف کردن سرویس‌ها:
```bash
docker compose down
```

### شروع سرویس‌ها:
```bash
docker compose up -d
```

### به‌روزرسانی سرویس‌ها:
```bash
docker compose pull
docker compose up -d
```

---

## مقیاس‌پذیری (Scale)

### تنظیم تعداد رپلیکاها در فایل .env:

```bash
# ویرایش فایل .env
nano .env

# تغییر تعداد رپلیکاها
PROCESSER_REPLICAS=10
ORDER_WORKER_REPLICAS=5
```

### اعمال تغییرات:
```bash
docker compose up -d
```

### مقیاس دستی:
```bash
# افزایش تعداد پردازشگرها
docker compose up -d --scale processor=10

# افزایش تعداد کارگرها
docker compose up -d --scale worker=5
```

---

## پشتیبان‌گیری

### پشتیبان از پایگاه داده:
```bash
# ایجاد پوشه پشتیبان
mkdir -p backups

# پشتیبان‌گیری
docker compose exec postgres pg_dump -U hossein digitalbot_db > backups/db_$(date +%Y%m%d_%H%M%S).sql
```

### بازیابی پایگاه داده:
```bash
# کپی فایل به کانتینر
docker compose cp backups/db_20240101_120000.sql postgres:/tmp/

# بازیابی
docker compose exec postgres psql -U hossein digitalbot_db < /tmp/db_20240101_120000.sql
```

### پشتیبان از تنظیمات:
```bash
# اسکریپت نصب به صورت خودکار پشتیبان می‌گیرد
# پشتیبان دستی:
cp .env .env.backup
cp docker-compose.yml docker-compose.yml.backup
```

---

## حل مشکلات رایج

### Docker شروع نمی‌شود:
```bash
# بررسی وضعیت
sudo systemctl status docker

# راه‌اندازی مجدد
sudo systemctl restart docker
```

### خطای Permission Denied:
```bash
# افزودن کاربر به گروه docker
sudo usermod -aG docker $USER

# خروج و ورود مجدد یا:
newgrp docker
```

### دامنه‌ها قابل دسترسی نیستند:
```bash
# بررسی DNS
nslookup your-domain.com

# بررسی Caddy
docker compose logs caddy

# بررسی پورت‌ها
sudo netstat -tulpn | grep -E ':(80|443)'
```

### خطای کمبود حافظه:
```bash
# بررسی حافظه
free -h
docker stats

# کاهش رپلیکاها
nano .env
# PROCESSER_REPLICAS=2
# ORDER_WORKER_REPLICAS=1

# راه‌اندازی مجدد
docker compose down
docker compose up -d
```

### خطای اتصال پایگاه داده:
```bash
# بررسی PostgreSQL
docker compose ps postgres

# بررسی لاگ
docker compose logs postgres

# تست اتصال
docker compose exec postgres psql -U hossein -d digitalbot_db
```

---

## امنیت

### نکات امنیتی مهم:

1. **رمز عبور قوی:**
   - حداقل 16 کاراکتر
   - ترکیبی از حروف، اعداد و علائم
   - از مدیر رمز عبور استفاده کنید

2. **فایروال:**
   ```bash
   # نصب UFW
   sudo apt install ufw
   
   # باز کردن پورت‌های لازم
   sudo ufw allow 22/tcp   # SSH
   sudo ufw allow 80/tcp   # HTTP
   sudo ufw allow 443/tcp  # HTTPS
   
   # فعال کردن
   sudo ufw enable
   ```

3. **به‌روزرسانی منظم:**
   ```bash
   # به‌روزرسانی سیستم
   sudo apt update && sudo apt upgrade
   
   # به‌روزرسانی Docker images
   docker compose pull
   docker compose up -d
   ```

4. **محدود کردن دسترسی:**
   - رابط‌های مدیریتی را فقط از IP خاص در دسترس قرار دهید
   - از VPN برای دسترسی به پنل‌های ادمین استفاده کنید

5. **مانیتورینگ:**
   - لاگ‌ها را به طور منظم بررسی کنید
   - لاگ تلگرام را فعال کنید
   - هشدارها را تنظیم کنید

---

## معماری توزیع شده

برای مقیاس‌پذیری بیشتر:

```
      لود بالانسر
           |
    +------+------+
    |             |
سرور اپ 1    سرور اپ 2
    |             |
    +------+------+
           |
    +------+------+------+
    |      |      |      |
 دیتابیس  Redis  MQ   Storage
```

### سرور دیتابیس:
```bash
./install.sh
# فقط PostgreSQL و PgAdmin
```

### سرور اپلیکیشن 1 و 2:
```bash
./install.sh
# اپلیکیشن‌ها، بدون دیتابیس
# در .env آدرس سرور دیتابیس را وارد کنید
```

---

## پشتیبانی

برای سوالات و مشکلات:
- مستندات کامل: `INSTALLATION_GUIDE.md`
- لاگ‌ها: `docker compose logs`
- Issue در GitHub

---

## مجوز

این پروژه تحت مجوز MIT منتشر شده است.
