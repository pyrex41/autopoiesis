package ws

import (
	"encoding/json"
	"fmt"
)

// plistToMap converts a JSON plist array ["key1", val1, "key2", val2, ...]
// into a map[string]any. If the input is already an object, it returns it as-is.
func plistToMap(raw json.RawMessage) (map[string]any, error) {
	// Try as object first
	var obj map[string]any
	if err := json.Unmarshal(raw, &obj); err == nil {
		return obj, nil
	}

	// Try as plist array
	var arr []any
	if err := json.Unmarshal(raw, &arr); err != nil {
		return nil, fmt.Errorf("not an object or plist array: %s", string(raw))
	}

	obj = make(map[string]any, len(arr)/2)
	for i := 0; i+1 < len(arr); i += 2 {
		key, ok := arr[i].(string)
		if !ok {
			continue
		}
		obj[key] = arr[i+1]
	}
	return obj, nil
}

// unmarshalPlist unmarshals a JSON value that may be either a JSON object
// or a Lisp-style plist array into the target struct.
func unmarshalPlist(raw json.RawMessage, target any) error {
	m, err := plistToMap(raw)
	if err != nil {
		return err
	}
	// Re-encode as proper JSON object and unmarshal
	data, err := json.Marshal(m)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, target)
}

// UnmarshalJSON implements custom unmarshaling for AgentData to handle plist arrays.
func (a *AgentData) UnmarshalJSON(data []byte) error {
	type Alias AgentData
	var alias Alias
	if err := unmarshalPlist(data, &alias); err != nil {
		return err
	}
	*a = AgentData(alias)
	return nil
}

// UnmarshalJSON implements custom unmarshaling for ThoughtData to handle plist arrays.
func (t *ThoughtData) UnmarshalJSON(data []byte) error {
	type Alias ThoughtData
	var alias Alias
	if err := unmarshalPlist(data, &alias); err != nil {
		return err
	}
	*t = ThoughtData(alias)
	return nil
}

// UnmarshalJSON implements custom unmarshaling for EventData to handle plist arrays.
func (e *EventData) UnmarshalJSON(data []byte) error {
	type Alias EventData
	var alias Alias
	if err := unmarshalPlist(data, &alias); err != nil {
		return err
	}
	*e = EventData(alias)
	return nil
}
