function stripHtml(value) {
  return String(value || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeDuckDuckGoRedirect(url) {
  const raw = String(url || '');
  const marker = 'uddg=';
  const idx = raw.indexOf(marker);
  if (idx < 0) {
    return raw;
  }
  try {
    return decodeURIComponent(raw.substring(idx + marker.length));
  } catch (_) {
    return raw;
  }
}

function pushUnique(results, seen, item) {
  const url = String(item.url || '').trim();
  if (!url || seen.has(url)) {
    return;
  }
  seen.add(url);
  results.push({
    title: String(item.title || 'Источник').trim(),
    url,
    snippet: String(item.snippet || '').trim(),
    source: String(item.source || 'web'),
  });
}

function flattenRelatedTopics(relatedTopics) {
  const flat = [];
  for (const item of relatedTopics || []) {
    if (Array.isArray(item.Topics)) {
      flat.push(...flattenRelatedTopics(item.Topics));
      continue;
    }
    flat.push(item);
  }
  return flat;
}

module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store, max-age=0');
  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Method Not Allowed' });
    return;
  }

  const query = String(req.query.q || '').trim();
  const limit = Math.max(1, Math.min(10, Number(req.query.limit || 6)));
  if (!query) {
    res.status(400).json({ error: 'Missing query parameter q' });
    return;
  }

  const results = [];
  const seen = new Set();

  try {
    const ddgUrl = new URL('https://api.duckduckgo.com/');
    ddgUrl.searchParams.set('q', query);
    ddgUrl.searchParams.set('format', 'json');
    ddgUrl.searchParams.set('no_html', '1');
    ddgUrl.searchParams.set('skip_disambig', '1');
    ddgUrl.searchParams.set('no_redirect', '1');

    const response = await fetch(ddgUrl.toString(), {
      headers: {
        Accept: 'application/json',
        'User-Agent': 'QuizTrainer/1.0 (+vercel)',
      },
    });

    if (response.ok) {
      const data = await response.json();
      if (data.AbstractURL && data.AbstractText) {
        pushUnique(results, seen, {
          title: data.Heading || 'DuckDuckGo',
          url: data.AbstractURL,
          snippet: stripHtml(data.AbstractText),
          source: 'duckduckgo',
        });
      }

      for (const item of data.Results || []) {
        pushUnique(results, seen, {
          title: stripHtml(item.Text) || 'DuckDuckGo',
          url: decodeDuckDuckGoRedirect(item.FirstURL),
          snippet: stripHtml(item.Text),
          source: 'duckduckgo',
        });
        if (results.length >= limit) {
          break;
        }
      }

      if (results.length < limit) {
        const related = flattenRelatedTopics(data.RelatedTopics || []);
        for (const item of related) {
          pushUnique(results, seen, {
            title: stripHtml(item.Text) || 'DuckDuckGo',
            url: decodeDuckDuckGoRedirect(item.FirstURL),
            snippet: stripHtml(item.Text),
            source: 'duckduckgo',
          });
          if (results.length >= limit) {
            break;
          }
        }
      }
    }
  } catch (_) {
    // Non-fatal: fallback sources below.
  }

  if (results.length < limit) {
    try {
      const wikiUrl = new URL('https://ru.wikipedia.org/w/api.php');
      wikiUrl.searchParams.set('action', 'query');
      wikiUrl.searchParams.set('list', 'search');
      wikiUrl.searchParams.set('format', 'json');
      wikiUrl.searchParams.set('utf8', '1');
      wikiUrl.searchParams.set('srlimit', String(limit));
      wikiUrl.searchParams.set('srsearch', query);

      const wikiResponse = await fetch(wikiUrl.toString(), {
        headers: {
          Accept: 'application/json',
          'User-Agent': 'QuizTrainer/1.0 (+vercel)',
        },
      });

      if (wikiResponse.ok) {
        const data = await wikiResponse.json();
        const hits =
          (data && data.query && Array.isArray(data.query.search)
            ? data.query.search
            : []);
        for (const hit of hits) {
          const title = String(hit.title || '').trim();
          if (!title) {
            continue;
          }
          pushUnique(results, seen, {
            title,
            url: `https://ru.wikipedia.org/wiki/${encodeURIComponent(
              title.replace(/\s+/g, '_'),
            )}`,
            snippet: stripHtml(hit.snippet),
            source: 'wikipedia',
          });
          if (results.length >= limit) {
            break;
          }
        }
      }
    } catch (_) {
      // Ignore fallback errors.
    }
  }

  res.status(200).json({
    query,
    count: results.length,
    results: results.slice(0, limit),
  });
};

