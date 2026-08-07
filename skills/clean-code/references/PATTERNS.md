# Refactoring Patterns

> Reference companion for the [clean-code](../SKILL.md) skill. Each pattern includes a concrete before/after diff.

## 1. Extract Function

Identical blocks across multiple call sites → single shared function.

```diff
# Before: validation logic duplicated in every handler
- func CreateUser(c *gin.Context) {
-     if c.GetHeader("Authorization") == "" {
-         c.JSON(401, gin.H{"error": "unauthorized"})
-         return
-     }
-     // ... create user
- }
- func CreateOrder(c *gin.Context) {
-     if c.GetHeader("Authorization") == "" {
-         c.JSON(401, gin.H{"error": "unauthorized"})
-         return
-     }
-     // ... create order
- }

# After: extracted into middleware
+ func AuthRequired() gin.HandlerFunc {
+     return func(c *gin.Context) {
+         if c.GetHeader("Authorization") == "" {
+             c.JSON(401, gin.H{"error": "unauthorized"})
+             c.Abort()
+             return
+         }
+         c.Next()
+     }
+ }
+ router.Use(AuthRequired())
```

## 2. Extract Constant/Config

Repeated magic values → named constant.

```diff
# Before: magic string scattered across files
- timeout := 30 * time.Second  // in api.go
- timeout := 30 * time.Second  // in worker.go
- timeout := 30 * time.Second  // in scheduler.go

# After: single source of truth
+ const DefaultTimeout = 30 * time.Second  // in config.go
+ timeout := config.DefaultTimeout          // everywhere else
```

## 3. Generic/Parameterized Function

Near-identical functions → one parameterized function.

```diff
# Before: duplicated logic in 3 handlers
- func GetUser(c *gin.Context) {
-     id := c.Param("id")
-     if id == "" { c.JSON(400, gin.H{"error": "id required"}); return }
-     user, err := db.FindUser(id)
-     if err != nil { c.JSON(404, gin.H{"error": "not found"}); return }
-     c.JSON(200, user)
- }
- func GetOrder(c *gin.Context) {
-     id := c.Param("id")
-     if id == "" { c.JSON(400, gin.H{"error": "id required"}); return }
-     order, err := db.FindOrder(id)
-     if err != nil { c.JSON(404, gin.H{"error": "not found"}); return }
-     c.JSON(200, order)
- }

# After: generic parameterized function
+ func getByID[T any](c *gin.Context, finder func(string) (T, error)) {
+     id := c.Param("id")
+     if id == "" { c.JSON(400, gin.H{"error": "id required"}); return }
+     result, err := finder(id)
+     if err != nil { c.JSON(404, gin.H{"error": "not found"}); return }
+     c.JSON(200, result)
+ }
+ func GetUser(c *gin.Context)  { getByID(c, db.FindUser) }
+ func GetOrder(c *gin.Context) { getByID(c, db.FindOrder) }
```

## 4. Template Method / Strategy

Similar flows with one varying step → design pattern.

```diff
# Before: report generators with duplicated structure
- func GeneratePDFReport(data []Record) {
-     validated := validate(data)
-     sorted := sortByDate(validated)
-     pdf := renderPDF(sorted)    // only this line differs
-     send(pdf)
- }
- func GenerateCSVReport(data []Record) {
-     validated := validate(data)
-     sorted := sortByDate(validated)
-     csv := renderCSV(sorted)    // only this line differs
-     send(csv)
- }

# After: strategy pattern
+ type Renderer func([]Record) []byte
+
+ func GenerateReport(data []Record, render Renderer) {
+     validated := validate(data)
+     sorted := sortByDate(validated)
+     output := render(sorted)
+     send(output)
+ }
+ GenerateReport(data, renderPDF)
+ GenerateReport(data, renderCSV)
```

## 5. Substitute Algorithm

Two functions reach the same result by different means → keep the better one, delete the other.

```diff
# Before: two CSV readers, both live, both maintained
- func ParseCSV(path string) ([]Record, error) {
-     data, err := os.ReadFile(path)              // whole file in memory
-     if err != nil { return nil, err }
-     var out []Record
-     for _, line := range strings.Split(string(data), "\n") {
-         if line == "" { continue }
-         cols := strings.Split(line, ",")        // breaks on quoted fields
-         out = append(out, Record{ID: cols[0], Name: cols[1]})
-     }
-     return out, nil
- }
- func LoadRecords(path string) ([]Record, error) {   // added later, same job
-     f, err := os.Open(path)
-     if err != nil { return nil, err }
-     defer f.Close()
-     var out []Record
-     r := csv.NewReader(f)                       // streams, handles quoting
-     for {
-         cols, err := r.Read()
-         if errors.Is(err, io.EOF) { break }
-         if err != nil { return nil, err }
-         out = append(out, Record{ID: cols[0], Name: cols[1]})
-     }
-     return out, nil
- }

# After: one implementation, every call site points at it
+ func ParseCSV(path string) ([]Record, error) {
+     f, err := os.Open(path)
+     if err != nil { return nil, err }
+     defer f.Close()
+     var out []Record
+     r := csv.NewReader(f)
+     for {
+         cols, err := r.Read()
+         if errors.Is(err, io.EOF) { break }
+         if err != nil { return nil, err }
+         out = append(out, Record{ID: cols[0], Name: cols[1]})
+     }
+     return out, nil
+ }
```

Choose the survivor on behavior, not aesthetics. Here the streaming version also handles quoted fields and embedded newlines, so keeping the shorter one would trade a duplication smell for a correctness bug. When both are equally correct, keep the one with more test coverage and delete the other in its own commit.

## 6. Replace Conditional with Polymorphism

The same `switch` / `if-elif` chain over a type discriminator, repeated across files → one dispatch point. This is the fix for **structural** duplication: the chain that forces N edits to add one case.

```diff
# Before: the same decision spelled out in three places
- func Send(n Notification) error {
-     switch n.Channel {
-     case "email": return sendEmail(n)
-     case "sms":   return sendSMS(n)
-     case "push":  return sendPush(n)
-     }
-     return fmt.Errorf("unknown channel %q", n.Channel)
- }
- func Retry(n Notification) error {
-     switch n.Channel {          // second copy of the same chain
-     case "email": return retryEmail(n)
-     case "sms":   return retrySMS(n)
-     case "push":  return retryPush(n)
-     }
-     return fmt.Errorf("unknown channel %q", n.Channel)
- }
- func TemplateFor(n Notification) string {
-     switch n.Channel {          // third copy — a new channel means three edits
-     case "email": return emailTemplate
-     case "sms":   return smsTemplate
-     case "push":  return pushTemplate
-     }
-     return ""
- }

# After: one interface, one registry — a new channel is one map entry
+ type Channel interface {
+     Send(Notification) error
+     Retry(Notification) error
+     Template() string
+ }
+
+ var channels = map[string]Channel{
+     "email": emailChannel{},
+     "sms":   smsChannel{},
+     "push":  pushChannel{},
+ }
+
+ func channelFor(name string) (Channel, error) {
+     c, ok := channels[name]
+     if !ok {
+         return nil, fmt.Errorf("unknown channel %q", name)
+     }
+     return c, nil
+ }
```

**Keep the unknown-case branch.** Polymorphism removes the repeated chain, not the need to reject invalid input — a registry miss must still return an error, never a silent zero value.

Try the cheap variant before the expensive one. A map from discriminator to handler solves most cases; a type hierarchy is only worth it when the cases carry several behaviors each, as above. A single `switch` that maps values to values (status code → label) and appears exactly once is not duplication — leave it alone. Extracting it is the premature abstraction that [SKILL.md](../SKILL.md) Phase 2 warns about.

Language variants: Python `functools.singledispatch` or a `dict` of callables — see [PYTHON.md](PYTHON.md); Rust one `enum` + `match` in a single place, or `Box<dyn Trait>` when the case set is open; TypeScript a `Record<Discriminator, Handler>` over a discriminated union, so the compiler flags a missing case instead of a runtime default.
