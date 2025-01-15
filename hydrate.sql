-- First enable the pgai extension
CREATE EXTENSION IF NOT EXISTS ai CASCADE;

-- Load the dataset from huggingface
SELECT ai.load_dataset(
    'wikimedia/wikipedia',  -- source dataset
    '20231101.en',         -- dataset version
    table_name=>'wiki',    -- table to create
    batch_size=>5,         -- number of rows per batch
    max_batches=>10         -- maximum number of batches to load
);

-- Add primary key to the wiki table
ALTER TABLE wiki ADD PRIMARY KEY (id);

-- Create the vectorizer
SELECT ai.create_vectorizer(
    'wiki'::regclass,
    destination => 'mini_wiki_embeddings',
    embedding => ai.embedding_ollama('all-minilm', 384),
    chunking => ai.chunking_recursive_character_text_splitter('text')
);


SELECT ai.create_vectorizer(
    'wiki'::regclass,
    destination => 'mistrai_wiki_embeddings',
    embedding => ai.embedding_ollama('mistral', 2048),
    chunking => ai.chunking_recursive_character_text_splitter('text')
);


CREATE OR REPLACE FUNCTION generate_rag_response(query_text TEXT, model_name TEXT default 'mistral')
RETURNS TEXT AS $$
DECLARE
   context_chunks TEXT;
   response TEXT;
BEGIN
   -- Perform similarity search to find relevant blog posts
   SELECT string_agg(title || ': ' || chunk, E'\n') INTO context_chunks
   FROM
   (
       SELECT title, chunk
       FROM blogs_embedding
       ORDER BY embedding <=> ai.ollama_embed(model, query_text)
       LIMIT 3
   ) AS relevant_posts;

   -- Generate a summary using llama3
   SELECT ai.ollama_chat_complete
   ( 'llama3'
   , jsonb_build_array
     ( jsonb_build_object('role', 'system', 'content', 'you are a helpful assistant')
     , jsonb_build_object
       ('role', 'user'
       , 'content', query_text || E'\nUse the following context to respond.\n' || context_chunks
       )
     )
   )->'message'->>'content' INTO response;

   RETURN response;
END;
$$ LANGUAGE plpgsql;
