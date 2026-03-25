# Realistic Load Test - User Abandonment Simulation

This scenario is experimental and outside the main checkout observability deliverable. The primary metrics, dashboard, and presentation focus on backend order placement after `Confirm Order`, not abandonment modelling.

## What It Is

`make load-realistic` simulates **realistic user behavior** with impatient users who abandon checkout if it's too slow.

## Load Profile

```
Time      | Users | What Happens
----------|-------|-------------
0-30s     | 0→10  | Warm up
30s-2m30s | 10→20 | Ramp to 20 concurrent users
2m30s-5m30s | 20  | Hold steady at 20 users
5m30s-6m  | 20→0  | Ramp down
```

**Total Duration**: 6 minutes

## Key Feature: 2-Second Timeout

**User patience threshold**: `timeout: '2s'`

This means:
- If any request (page load or POST) takes >2 seconds → **User abandons**
- Realistic: Real users abandon slow checkouts
- Triggers dropoff metrics automatically

## Expected Behaviors & Errors

### 1. Timeout-Based Dropoff (Most Common)

**When**: System under load, requests take >2s

**What happens:**
- Attempt recorded: ✅ `RecordStageAttempt("payment")`
- Timeout occurs: ❌ Request fails, user abandons
- **No completion recorded** → Dropoff!

**Metrics:**
- `attempts_total`: Increases
- `completions_total`: Does NOT increase
- **Dropoff Rate**: `(attempts - completions) / attempts`
- **Subsystem**: `general` (timeout, not subsystem-specific)

**Example:**
```
Dropoff Rate by Stage:
- prepare: 5% (most complete quickly)
- payment: 15% (some timeout waiting for DB)
- persist_order: 20% (DB write times out)
```

---

### 2. Minimum Order Interval Errors (If Enabled)

**When**: User tries to checkout too quickly after previous order

**What happens:**
- Attempt recorded: ✅
- Validation fails: ❌ "Minimum 5 minutes between orders"
- Completion recorded: ✅ (failure)

**Metrics:**
- `outcome="failure"`
- `reason_code="minimum_interval"`
- `subsystem="order_processing"`

**To trigger this:**
```bash
# Before running load-realistic, enable minimum interval:
make load-min-interval  # Sets 5-minute minimum
# Then Ctrl+C after first iteration
# Then run: make load-realistic
```

---

### 3. Natural Validation Errors

**When**: Random edge cases during high concurrency

**Potential errors:**
- Empty cart (if session issues)
- Terms not accepted
- Invalid payment data

**Metrics:**
- `subsystem="basket"` - Cart validation
- `subsystem="payment_provider"` - Payment validation
- `reason_code` varies by error type

---

## What Dashboards Will Show

### Checkout Funnel - Attempts vs Completions
```
prepare:     20 attempts, 19 completions  (5% dropoff)
payment:     19 attempts, 16 completions  (16% dropoff)
persist:     16 attempts, 15 completions  (6% dropoff)
finalize:    15 attempts, 15 completions  (0% dropoff)
```

**Gap between lines = user abandonment!**

### Dropoff Rate by Stage (%)
```
prepare:     ~5%  (green)
payment:     ~15% (yellow - some timeouts)
persist:     ~6%  (green)
move_items:  ~5%  (green)
finalize:    ~0%  (green - if you get here, you complete)
```

### Failures by Subsystem
If system is slow enough to cause timeouts:
```
general: 0.5 failures/sec  (timeout errors)
order_processing: 0.1 failures/sec (if min interval enabled)
```

### Stage Success Rate
```
prepare:     95% ✓
payment:     85% ⚠️ (some timeouts)
persist:     94% ✓
finalize:    100% ✓
```

### Checkout Error Rate (%)
**Overall:** 10-20% (mix of timeouts + any validation errors)

---

## How to Use

### Quick Test (Normal Stack)
```bash
make up
make load-realistic
```

**Expected result:**
- Most checkouts succeed
- Some dropoff if system is slightly slow
- Error rate: 5-10%

---

### Stress Test (Resource Constrained)
```bash
make up-loadtest  # Database bottleneck
make load-realistic
```

**Expected result:**
- Database slow → more timeouts
- Higher dropoff rate (15-25%)
- Error rate: 15-25%
- Clear funnel visualization showing leakage

---

### Maximum Diversity (Minimum Interval + Realistic)

**Step 1:** Set minimum interval
```bash
docker exec nopcommerce_mssql_server /opt/mssql-tools18/bin/sqlcmd \
  -C -S localhost -U sa -P nopCommerce_db_password \
  -d nopCommerce \
  -Q "UPDATE [Setting] SET [Value] = '3' WHERE [Name] = 'ordersettings.minimumorderplacementinterval';"

docker restart nopcommerce
```

**Step 2:** Wait for restart, then run test
```bash
make load-realistic
```

**Expected result:**
- First checkout per user: ✅ Success
- Subsequent checkouts: ❌ Minimum interval failure
- **Subsystem variety:**
  - `order_processing` (minimum interval)
  - `general` (timeouts)
- Error rate: 20-40%

**Step 3:** Reset (important!)
```bash
docker exec nopcommerce_mssql_server /opt/mssql-tools18/bin/sqlcmd \
  -C -S localhost -U sa -P nopCommerce_db_password \
  -d nopCommerce \
  -Q "UPDATE [Setting] SET [Value] = '1' WHERE [Name] = 'ordersettings.minimumorderplacementinterval';"

docker restart nopcommerce
```

---

## Comparison to Other Load Tests

| Test | VUs | Duration | Timeout | Failures Generated |
|------|-----|----------|---------|-------------------|
| `make load-5` | 5 | 24h | 10s | Very few (system handles easily) |
| `make load-20` | 20 | ~3m | 10s | Very few |
| **`make load-realistic`** | **20** | **6m** | **2s** | **10-25% (timeouts + validation)** |
| `make load-degrade` | 15→40 | 4.5m | 10s | 15-30% (degradation) |
| `make load-min-interval` | 1 | 90s | 10s | 90% (all fail after first) |

---

## Why 2 Seconds?

**Real user behavior studies show:**
- 47% of users expect pages to load in <2s
- 40% abandon after 3s wait
- Every 1s delay = ~7% drop in conversions

**2-second timeout simulates impatient users** - a realistic scenario where:
- Users tap "Submit" → Wait → Get frustrated → Close tab
- Your metrics capture this as: **Attempt recorded, completion missing = Dropoff**

---

## TL;DR

```bash
# Best for demonstrating new metrics:
make up
make load-realistic
```

**You'll see:**
- ✅ Funnel visualization (attempts vs completions)
- ✅ Dropoff rate (10-20% typical)
- ✅ Subsystem failures (if errors occur)
- ✅ Success rate degradation (payment stage most affected)
- ✅ Realistic user abandonment patterns

**Perfect for assignment screenshots!**
