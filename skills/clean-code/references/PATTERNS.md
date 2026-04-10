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
