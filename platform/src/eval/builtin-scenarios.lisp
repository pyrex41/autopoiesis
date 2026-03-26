;;;; builtin-scenarios.lisp - Pre-built evaluation scenario library
;;;;
;;;; Provides ready-to-use scenarios across multiple domains for
;;;; evaluating agent systems. Each scenario includes a prompt,
;;;; verifier, and optional rubric for LLM-as-judge scoring.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Scenario Library Registration
;;; ===================================================================

(defvar *builtin-scenarios-loaded* nil
  "Track whether builtin scenarios have been loaded to avoid duplicates.")

(defun load-builtin-scenarios ()
  "Register all built-in evaluation scenarios.
   Safe to call multiple times — only loads once per store."
  (when *builtin-scenarios-loaded*
    (return-from load-builtin-scenarios nil))

  ;; ── Coding: Basic ──────────────────────────────────────────

  (create-scenario
   :name "FizzBuzz"
   :description "Implement the classic FizzBuzz program"
   :prompt "Write a function called fizzbuzz that takes an integer n and returns a list of strings for numbers 1 through n. For multiples of 3 return \"Fizz\", for multiples of 5 return \"Buzz\", for multiples of both return \"FizzBuzz\", otherwise return the number as a string."
   :domain :coding
   :tags '(:basic :algorithm)
   :verifier '(:type :contains :value "FizzBuzz")
   :rubric "Evaluate for: correctness (handles all cases), code quality (clean, readable), edge cases (n=0, n=1, n=15)")

  (create-scenario
   :name "Reverse String"
   :description "Implement string reversal without built-in reverse"
   :prompt "Write a function called reverse-string that takes a string and returns it reversed. Do not use any built-in reverse function. Handle empty strings and single-character strings correctly."
   :domain :coding
   :tags '(:basic :string)
   :verifier '(:type :contains :value "reverse")
   :rubric "Evaluate for: correctness, handles edge cases (empty, single char, unicode), efficiency (O(n) time)")

  (create-scenario
   :name "Binary Search"
   :description "Implement binary search on a sorted array"
   :prompt "Write a function called binary-search that takes a sorted array of integers and a target value, and returns the index of the target if found, or -1 if not found. The function must run in O(log n) time."
   :domain :coding
   :tags '(:basic :algorithm :search)
   :verifier '(:type :contains :value "binary")
   :rubric "Evaluate for: correctness (finds/misses targets), O(log n) complexity, edge cases (empty array, single element, target not present)")

  ;; ── Coding: Data Structures ──────────────────────────────────

  (create-scenario
   :name "Stack Implementation"
   :description "Implement a stack data structure with push, pop, peek"
   :prompt "Implement a Stack class/structure with methods: push(value), pop() returning the value, peek() returning the top without removing, is_empty() returning boolean, and size() returning the count. Pop and peek on empty stack should signal an error or return nil."
   :domain :coding
   :tags '(:data-structure :stack)
   :verifier :non-empty
   :rubric "Evaluate for: correct LIFO behavior, error handling on empty stack, clean API design, all methods implemented")

  (create-scenario
   :name "Hash Map"
   :description "Implement a simple hash map with get, set, delete"
   :prompt "Implement a HashMap/Dictionary class with methods: set(key, value), get(key) returning the value or nil, delete(key) removing the entry, contains(key) returning boolean, and keys() returning all keys. Handle collisions appropriately."
   :domain :coding
   :tags '(:data-structure :hash-map)
   :verifier :non-empty
   :rubric "Evaluate for: correct behavior for all operations, collision handling strategy, key iteration, edge cases (overwrite existing key, delete nonexistent)")

  ;; ── Coding: File I/O ──────────────────────────────────────────

  (create-scenario
   :name "CSV Parser"
   :description "Parse a CSV string handling quoted fields"
   :prompt "Write a function called parse-csv that takes a CSV string and returns a list of rows, where each row is a list of field values. Handle quoted fields (fields containing commas or newlines wrapped in double quotes), and escaped quotes (\"\" inside quoted fields)."
   :domain :coding
   :tags '(:parsing :csv :io)
   :verifier :non-empty
   :rubric "Evaluate for: handles basic CSV, quoted fields with commas, escaped quotes, empty fields, trailing newlines")

  (create-scenario
   :name "JSON Formatter"
   :description "Pretty-print a JSON string with proper indentation"
   :prompt "Write a function called format-json that takes a compact JSON string and returns a pretty-printed version with 2-space indentation. Handle objects, arrays, strings, numbers, booleans, and null."
   :domain :coding
   :tags '(:formatting :json :io)
   :verifier '(:type :contains :value "{")
   :rubric "Evaluate for: correct indentation, handles nested objects/arrays, preserves string content, handles all JSON types")

  ;; ── Refactoring ──────────────────────────────────────────────

  (create-scenario
   :name "Extract Method"
   :description "Refactor a long function by extracting methods"
   :prompt "The following function does too many things. Refactor it by extracting at least 3 well-named helper functions:

```
function processOrder(order) {
  // Validate
  if (!order.items || order.items.length === 0) throw new Error('Empty order');
  if (!order.customer || !order.customer.email) throw new Error('No customer');
  // Calculate totals
  let subtotal = 0;
  for (const item of order.items) {
    subtotal += item.price * item.quantity;
  }
  const tax = subtotal * 0.08;
  const shipping = subtotal > 100 ? 0 : 9.99;
  const total = subtotal + tax + shipping;
  // Format receipt
  let receipt = `Order for ${order.customer.name}\\n`;
  receipt += `Items: ${order.items.length}\\n`;
  receipt += `Subtotal: $${subtotal.toFixed(2)}\\n`;
  receipt += `Tax: $${tax.toFixed(2)}\\n`;
  receipt += `Shipping: $${shipping.toFixed(2)}\\n`;
  receipt += `Total: $${total.toFixed(2)}`;
  return { total, receipt };
}
```"
   :domain :refactoring
   :tags '(:extract-method :code-quality)
   :verifier :non-empty
   :rubric "Evaluate for: meaningful function names, single responsibility per function, preserved behavior, improved readability, no duplication")

  (create-scenario
   :name "Add Error Handling"
   :description "Add proper error handling to fragile code"
   :prompt "Add comprehensive error handling to this function that reads a config file and connects to a database. Handle file not found, invalid JSON, missing required fields, and connection failures. Return meaningful error messages.

```
async function initializeApp(configPath) {
  const data = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(data);
  const db = await connect(config.database.host, config.database.port);
  await db.query('SELECT 1');
  return { db, config };
}
```"
   :domain :refactoring
   :tags '(:error-handling :robustness)
   :verifier '(:type :contains :value "catch")
   :rubric "Evaluate for: all failure modes handled (file, JSON, fields, connection), specific error messages, graceful degradation, resource cleanup")

  ;; ── Research / Analysis ──────────────────────────────────────

  (create-scenario
   :name "Compare Approaches"
   :description "Compare two technical approaches with trade-offs"
   :prompt "Compare microservices vs monolith architecture for a new e-commerce platform that needs to handle 10,000 concurrent users. Cover: development speed, operational complexity, scalability, team size requirements, and cost. Recommend one approach with justification."
   :domain :research
   :tags '(:architecture :comparison :analysis)
   :verifier :non-empty
   :rubric "Evaluate for: covers all requested dimensions, balanced analysis (pros/cons for both), specific to the use case (10K users, e-commerce), clear recommendation with reasoning, acknowledges trade-offs")

  (create-scenario
   :name "Summarize Technical Document"
   :description "Summarize a technical concept clearly"
   :prompt "Explain the CAP theorem in distributed systems. Cover: what it states, why you can only pick 2 of 3, give a real-world example for each pair (CP, AP, CA), and explain which pair is most common in practice and why."
   :domain :research
   :tags '(:explanation :distributed-systems)
   :verifier '(:type :contains :value "CAP")
   :rubric "Evaluate for: accurate definition, correct 2-of-3 explanation, concrete examples for each pair, practical guidance, accessible to a mid-level engineer")

  ;; ── Tool Use / Integration ──────────────────────────────────

  (create-scenario
   :name "Git Workflow"
   :description "Execute a git branching workflow"
   :prompt "Create a new git branch called 'feature/auth', make a commit with the message 'Add authentication module', then list the branches showing the new branch exists. Show the exact git commands you would run."
   :domain :tool-use
   :tags '(:git :workflow)
   :verifier '(:type :contains :value "feature/auth")
   :rubric "Evaluate for: correct git commands, proper branch naming, commit message quality, commands in logical order")

  (create-scenario
   :name "API Integration"
   :description "Write code to call a REST API with error handling"
   :prompt "Write a function that fetches a user profile from a REST API at GET /api/users/{id}. Handle: successful response (return parsed JSON), 404 (return nil), rate limiting (429 — retry with exponential backoff up to 3 attempts), and network errors. Include proper headers (Accept: application/json, Authorization: Bearer <token>)."
   :domain :tool-use
   :tags '(:api :http :error-handling)
   :verifier :non-empty
   :rubric "Evaluate for: correct HTTP method/headers, all status codes handled, exponential backoff implementation, clean error handling, auth token usage")

  ;; ── Reasoning / Logic ──────────────────────────────────────────

  (create-scenario
   :name "Debug Logic Error"
   :description "Find and fix a subtle logic bug"
   :prompt "This function should return true if a number is prime, but it has a bug. Find the bug, explain why it's wrong, and provide the corrected version.

```
function isPrime(n) {
  if (n < 2) return false;
  for (let i = 2; i < n; i++) {
    if (n % i === 0) return true;
  }
  return false;
}
```"
   :domain :reasoning
   :tags '(:debugging :logic)
   :verifier '(:type :contains :value "return false")
   :expected "The bug is that the function returns true when it finds a divisor (should return false) and returns false when no divisor is found (should return true). The return values are swapped."
   :rubric "Evaluate for: correctly identifies the swapped returns, clear explanation of why it's wrong, correct fix, mentions optimization opportunity (sqrt(n))")

  (create-scenario
   :name "Multi-Step Problem"
   :description "Solve a multi-step reasoning problem"
   :prompt "A store has a 'buy 2, get 1 free' promotion where the cheapest item is free. A customer buys items costing $30, $20, $15, $10, and $5. Calculate: (1) which items are free, (2) the total price paid, (3) the total savings. Show your work step by step."
   :domain :reasoning
   :tags '(:math :multi-step :logic)
   :verifier '(:type :regex :value "\\$?[67][05]")
   :expected "Groups: ($30,$20,$15) free=$15, ($10,$5) free=$5. Total paid = $30+$20+$10 = $60. Wait — need to regroup. Groups: ($30,$20,$15)->free $15; ($10,$5)->only 2 items, no free item. Total: $30+$20+$10+$5 = $65. Savings: $15."
   :rubric "Evaluate for: correct grouping strategy, correct identification of free items, accurate arithmetic, clear step-by-step reasoning")

  ;; ── Sandbox: Filesystem Operations ──────────────────────────────

  (create-scenario
   :name "Create Project Structure"
   :description "Create a standard Python project directory layout"
   :prompt "mkdir -p src tests && echo 'def hello(): return \"Hello, world!\"' > src/main.py && echo 'from src.main import hello\ndef test_hello(): assert hello() == \"Hello, world!\"' > tests/test_main.py && echo 'pytest' > requirements.txt && echo '# My Project' > README.md && echo done"
   :domain :sandbox
   :tags '(:filesystem :project-setup)
   :verifier :file-exists
   :expected "src/main.py"
   :rubric "Evaluate for: all files created, correct content, proper project structure")

  (create-scenario
   :name "Refactor File Organization"
   :description "Reorganize flat files into module directories"
   :prompt "mkdir -p core api common && mv utils.py common/ 2>/dev/null; mv models.py core/ 2>/dev/null; mv db.py core/ 2>/dev/null; mv views.py api/ 2>/dev/null; mv auth.py api/ 2>/dev/null; touch core/__init__.py api/__init__.py common/__init__.py && echo done"
   :domain :sandbox
   :tags '(:filesystem :refactoring)
   :verifier :tree-matches
   :expected '("core/__init__.py" "api/__init__.py" "common/__init__.py")
   :rubric "Evaluate for: all directories created, init files present, logical grouping")

  (create-scenario
   :name "Write Configuration File"
   :description "Create a JSON configuration file with production settings"
   :prompt "echo '{\"port\": 8080, \"host\": \"0.0.0.0\", \"debug\": false, \"log_level\": \"INFO\"}' > config.json && echo done"
   :domain :sandbox
   :tags '(:filesystem :configuration)
   :verifier :file-exists
   :expected "config.json"
   :rubric "Evaluate for: valid JSON, correct production values, all fields present")

  (setf *builtin-scenarios-loaded* t)
  (length (list-scenarios)))
