\* mvfs/scalars.shen — scalar type synonyms (loaded FIRST, before any file that
   uses these names in a signature). hash/id/principal/path are readable aliases
   for string in v1 (git SHA-256 hex / opaque strings). The load-bearing nominal
   types are the FSM states + capabilities in fsm.shen, not these. *\
(package mvfs [] (synonyms hash string id string principal string path string))
